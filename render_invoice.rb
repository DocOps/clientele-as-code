require 'safe_yaml'
require 'liquid'
require 'fileutils'

SafeYAML::OPTIONS[:default_mode] = :safe

if ARGV.include?('--adoc')
  adoc_index = ARGV.index('--adoc')
  adoc_file = ARGV[adoc_index + 1]
  ARGV.delete_at(adoc_index)
  ARGV.unshift(adoc_file)
end

client_slug = ARGV[0]
invoice_id_arg = ARGV[1]

if client_slug.nil?
  puts 'Usage: bundle exec render_invoice.rb <client-name> [invoice-number]'
  exit 1
end

# check first for _clientelle.yml and then for _config.yml
config_path = if File.exist?('_clientelle.yml')
  '_clientelle.yml'
else
  '_config.yml'
end

unless File.exist?(config_path)
  puts "Error: Configuration file '#{config_path}' not found."
  exit 1
end
config = YAML.load_file(config_path)

clients_dir = config['settings']['clients_dir'] || 'clients'



# Load YAML data from the client-specific file
client_meta_path = "#{clients_dir}/#{client_slug}/_client.yml"

unless File.exist?(client_meta_path)
  puts "Error: Client meta file '#{client_meta_path}' not found."
  exit 1
end

payments_path = config['settings']['payments_path'] || '_payments.yml'
payments_file_path = "clients/#{client_slug}/#{payments_path}"

unless File.exist?(payments_file_path)
  puts "Error: Client payments file '#{payments_file_path}' not found."
  exit 1
end

client_data = YAML.load_file(client_meta_path)
payments_data = YAML.load_file(payments_file_path)
invoices = payments_data['invoices']

# Determine the invoice to generate
selected_invoice = if invoice_id_arg
  invoices.find do |inv|
    # Check if inv['id'] is an integer and format it, or use the string directly
    inv_id_str = inv['id'].is_a?(Integer) ? format('%03d', inv['id']) : inv['id'].to_s
    inv_id_str == invoice_id_arg
  end
else
  invoices.first
end
# If no invoice is found, exit
if selected_invoice.nil?
  puts invoice_id_arg ? "Error: Invoice ##{invoice_id_arg} not found." : "No invoices available for client '#{client_slug}'."
  exit 1
end

# Extract invoice details
invoice_id = selected_invoice['id']
date_issued = selected_invoice['dates']['sent']
output_dir = config['settings']['output_dir'] || 'invoices'
output_dir = "#{clients_dir}/#{client_slug}/#{output_dir}"
invoice_overdue = selected_invoice['dates']['due'] < Date.today && !selected_invoice['dates']['paid']
selected_invoice['overdue'] = true if invoice_overdue
invoice_paid = selected_invoice['dates']['paid']
assets_path = '../' * (output_dir.split('/').length) + 'assets'
selected_invoice['assets_path'] = assets_path
provider_slug = "#{config['provider']['slug']}-" || ''
output_base = "#{provider_slug}invoice-#{client_slug}-#{invoice_id}-#{date_issued}#{invoice_paid ? '-PAID' : ''}#{invoice_overdue ? '-OVERDUE' : ''}"
output_html = "#{output_dir}/#{output_base}.html"
output_pdf = "#{output_dir}/#{output_base}.pdf"
keep_asciidoc = config['settings']['keep_asciidoc'].nil? ? true : config['settings']['keep_asciidoc']

# Ensure output directory exists
FileUtils.mkdir_p(output_dir)

# LIQUID
module CustomFilters
  def number_delimited(input)
    integer_part, decimal_part = input.to_s.split('.')
    formatted_integer = integer_part.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    if decimal_part
      "#{formatted_integer}.#{decimal_part}"
    else
      formatted_integer
    end
  end
  def format_decimal(input)
    num_float = input.to_f
    num_int = input.to_i
    if num_float == num_int
      "#{num_int}.00"
    else
      sprintf("%.2f", num_float)
    end
  end
end
Liquid::Template.register_filter(CustomFilters)

# Load Liquid template
template = File.read('templates/invoice.asciidoc')
renderer = Liquid::Template.parse(template)
output_adoc = renderer.render('client' => client_data, 'invoice' => selected_invoice, 'provider' => config['provider'], 'config' => config['settings'])

# Write AsciiDoc output to temporary file
adoc_file = "#{output_dir}/#{output_base}.adoc"
File.write(adoc_file, output_adoc)

# Convert to HTML
system("asciidoctor -o #{output_html} #{adoc_file}")

# Convert to PDF
system("asciidoctor-pdf -o #{output_pdf} --theme assets/pdf-theme.yml #{adoc_file}")

# Clean up temporary AsciiDoc file
File.delete(adoc_file) unless keep_asciidoc

puts "Generated files: #{output_html} and #{output_pdf}"