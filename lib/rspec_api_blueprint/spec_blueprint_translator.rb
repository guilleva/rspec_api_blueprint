class SpecBlueprintTranslator
  def init(example)
    @action_group = example.example_group.metadata
    @resource_group = @action_group[:parent_example_group]
    @grouping_group = @resource_group[:parent_example_group]

    @handle = File.open(file_path, 'a')
  end

  def flush
    write_resource_if_first(file, resource, resource_description)
    write_action(action, action_description)
    write_request
    write_response
    @handle.close
  end

  def file_path
    @grouping_group[:description_args].first.match(/(.+)\sRequests/)
    file_name = $1.gsub(' ','').underscore

    "#{api_docs_folder_path}#{file_name}_blueprint.md"
  end

  def write_resource_if_first(file)
    @resource_group[:description_args].first.match(/(.+)\[(.+)\]/)
    resource_description = $1
    resource = $2

    unless File.readlines(file).grep(%r{#{resource}}).any?
      @handle.write "## #{resource_description} [#{resource}]"
      @handle.write("\n")
    end
  end

  def write_action
    @action_group[:description_args].first.match(/(.+)\[(.+)\]/)
    action_description = $1
    action = $2.upcase

    @handle.write "### #{action_description} [#{action}]"

    query_strings = URI.decode(request.env['QUERY_STRING']).split('&')

    params = query_strings.map do |value|
      value.gsub("[","%5B").gsub("]","%5D")
    end

    unless params.empty?
     @handle.write "?#{params.join('&')}"
    end

    @handle.write("\n")
  end

  def write_request
    request_body = request.body.read

    current_env  = request.env ? request.env : request.headers

    authorization_header = current_env['HTTP_AUTHORIZATION']   ||
      env['X-HTTP_AUTHORIZATION'] ||
      env['X_HTTP_AUTHORIZATION'] ||
      env['REDIRECT_X_HTTP_AUTHORIZATION'] ||
      env['AUTHORIZATION']


    if request_body.present? || authorization_header.present? || request.env['QUERY_STRING']
      @handle.write "+ Request #{request.content_type}\n\n"

      if request.env['QUERY_STRING'].present?
        @handle.write "+ Parameters\n\n".indent(4)
        query_strings = URI.decode(request.env['QUERY_STRING']).split('&')

        query_strings.each do |value|
          key, example = value.split('=')
          @handle.write "+ #{key} = '#{example}'\n".indent(12)
        end
        @handle.write("\n")
      end

      allowed_headers = %w(HTTP_AUTHORIZATION AUTHORIZATION CONTENT_TYPE)
      @handle.write "+ Headers\n\n".indent(4)
      current_env.each do |header, value|
        next unless allowed_headers.include?(header)
        header = header.gsub(/HTTP_/, '') if header == 'HTTP_AUTHORIZATION'
        @handle.write "#{header}: #{value}\n".indent(12)
      end
      @handle.write "\n"

      # Request Body
      if request_body.present? && request.content_type.to_s == 'application/json'
        @handle.write "+ Body\n\n".indent(4) if authorization_header
        @handle.write "#{JSON.pretty_generate(JSON.parse(request_body))}\n\n".indent(authorization_header ? 12 : 8)
      end
    end
  end

  def write_response
    @handle.write "+ Response #{response.status} (#{response.content_type}; charset=#{response.charset})\n\n"

    if response.body.present? && response.content_type.to_s =~ /application\/json/
      @handle.write "#{JSON.pretty_generate(JSON.parse(response.body))}\n\n".indent(8)
    end
  end
end
