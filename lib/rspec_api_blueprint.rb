require "rspec_api_blueprint/version"
require "rspec_api_blueprint/string_extensions"


RSpec.configure do |config|
  config.before(:suite) do
    if defined? Rails
      api_docs_folder_path = File.join(Rails.root, '/docs/', '/api_docs/')
    else
      api_docs_folder_path = File.join(File.expand_path('.'), '/api_docs/')
    end

    Dir.mkdir(api_docs_folder_path) unless Dir.exists?(api_docs_folder_path)

    Dir.glob(File.join(api_docs_folder_path, '*_blueprint.md')).each do |f|
      File.delete(f)
    end
  end

  config.after(:suite) do

    if defined? Rails
      api_docs_folder_path = File.join(Rails.root, '/docs/', '/api_docs/')
    else
      api_docs_folder_path = File.join(File.expand_path('.'), '/api_docs/')
    end

    append = ->(handle, file){ handle.puts File.read(File.join(api_docs_folder_path, file)) }

    File.open(File.join(api_docs_folder_path ,'apiary.apib'), 'wb') do |apiary|
      append.call(apiary, 'introduction.md')

      Dir[File.join(api_docs_folder_path, '*_blueprint.md')].each do |file|
        header = file.gsub('_blueprint.md', '_header.md')

        if File.exists? header
          append.call(apiary, File.basename(header))
        end

        append.call(apiary, File.basename(file))
      end
    end
  end

  config.after(:each, type: :request) do |example|
    next unless example.metadata[:document] === true

    if response
      example_group = example.example_group.metadata
      example_groups = []

      while example_group
        example_groups << example_group
        example_group = example_group[:parent_example_group]
      end

      if example_groups[-2]
        action = example_groups[-2][:description_args].first
        extra_description = example_groups[-2][:extra_documentation]
      end
      example_groups[-1][:description_args].first.match(/(.+)\sRequests/)
      file_name = $1.gsub(' ','').underscore

      if defined? Rails
        file = File.join(Rails.root, "/docs/api_docs/#{file_name}_blueprint.md")
      else
        file = File.join(File.expand_path('.'), "/api_docs/#{file_name}_blueprint.md")
      end


      File.open(file, 'a') do |f|
        # Resource & Action
        f.write "# #{action}\n"
        if extra_description.present?
          f.write File.read(File.join(Rails.root, '/docs/api_docs', extra_description))
        end

        # Request
        request_body = request.body.read

        current_env  = request.env ? request.env : request.headers

        authorization_header = current_env['HTTP_AUTHORIZATION']   ||
          env['X-HTTP_AUTHORIZATION'] ||
          env['X_HTTP_AUTHORIZATION'] ||
          env['REDIRECT_X_HTTP_AUTHORIZATION'] ||
          env['AUTHORIZATION']


        if request_body.present? || authorization_header.present? || request.env['QUERY_STRING']
          f.write "+ Request #{request.content_type}\n\n"

          if request.env['QUERY_STRING'].present?
            f.write "+ Parameters\n\n".indent(4)
            query_strings = URI.decode(request.env['QUERY_STRING']).split('&')

            query_strings.each do |value|
              key, example = value.split('=')
              f.write "+ #{key} = '#{example}'\n".indent(12)
            end
            f.write("\n")
          end

          allowed_headers = %w(HTTP_AUTHORIZATION X-HTTP_AUTHORIZATION X_HTTP_AUTHORIZATION REDIRECT_X_HTTP_AUTHORIZATION AUTHORIZATION CONTENT_TYPE)
          f.write "+ Headers\n\n".indent(4)
          current_env.each do |header, value|
            next unless allowed_headers.include?(header)
            f.write "#{header}: #{value}\n".indent(12)
          end
          f.write "\n"

          # Request Body
          if request_body.present? && request.content_type.to_s == 'application/json'
            f.write "+ Body\n\n".indent(4) if authorization_header
            f.write "#{JSON.pretty_generate(JSON.parse(request_body))}\n\n".indent(authorization_header ? 12 : 8)
          end
        end

        # Response
        f.write "+ Response #{response.status} (#{response.content_type}; charset=#{response.charset})\n\n"

        if response.body.present? && response.content_type.to_s =~ /application\/json/
          f.write "#{JSON.pretty_generate(JSON.parse(response.body))}\n\n".indent(8)
        end
      end unless response.status == 401 || response.status == 403 || response.status == 301
    end
  end
end
