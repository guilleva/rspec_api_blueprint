require 'rspec_api_blueprint/version'
require 'rspec_api_blueprint/string_extensions'
require 'rspec_api_blueprint/spec_blueprint_translator'

RSpec.configure do |config|
  config.before(:suite) do
    Dir.mkdir(api_docs_folder_path) unless Dir.exist?(api_docs_folder_path)

    Dir.glob(File.join(api_docs_folder_path, '*_blueprint.md')).each do |f|
      File.delete(f)
    end
  end

  config.after(:suite) do
    append = -> (handle, file) { handle.puts File.read(File.join(api_docs_folder_path, file)) }

    File.open(File.join(api_docs_folder_path, 'apiary.apib'), 'wb') do |apiary|
      append.call(apiary, 'introduction.md')

      Dir[File.join(api_docs_folder_path, '*_blueprint.md')].each do |file|
        header = file.gsub('_blueprint.md', '_header.md')

        if File.exist? header
          append.call(apiary, File.basename(header))
        else
          apiary.puts "# Group #{(File.basename(file, '_blueprint.md')).titleize}"
        end

        append.call(apiary, File.basename(file))
      end
    end
  end

  config.after(:each, type: :request) do |example|
    translator = SpecBlueprintTranslator.new(example, request, response)

    if translator.can_make_blueprint?
      translator.open_file_from_grouping
      translator.write_resource_to_file
      translator.write_action_to_file
      translator.close_file
    end
  end
end

def api_docs_folder_path
  return File.join(Rails.root, '/doc/', '/api_docs/') if defined? Rails

  File.join(File.expand_path('.'), '/api_docs/')
end
