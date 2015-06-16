class SpecBlueprintTranslator
  @@actions_covered = {}

  def initialize(example, request, response)
    group_metas = []
    group_meta = example.example_group.metadata

    while group_meta.present?
      group_metas << group_meta
      group_meta = group_meta[:parent_example_group]
    end

    @example = example
    @action_group = group_metas[-3]
    @resource_group = group_metas[-2]
    @grouping_group = group_metas[-1]

    @request = request
    @response = response
  end

  def can_make_blueprint?
    @action_group.present? && @resource_group.present? && @grouping_group.present? && @example.metadata[:document] === true && basic_status?
  end

  def basic_status?
    response.status == 200 || response.status == 201 || response.status == 202
  end

  attr_reader :request

  attr_reader :response

  def resource
    @resource_group[:description_args].first.match(/(.+)\[(.+)\]/)
    Regexp.last_match(2)
  end

  def resource_description
    @resource_group[:description_args].first.match(/(.+)\[(.+)\]/)
    Regexp.last_match(1)
  end

  def action
    @action_group[:description_args].first.match(/(.+)\[(.+)\]/)
    Regexp.last_match(2).upcase
  end

  def action_description
    @action_group[:description_args].first.match(/(.+)\[(.+)\]/)
    Regexp.last_match(1)
  end

  def open_file_from_grouping
    @handle = File.open(file_path, 'a')
  end

  def close_file
    @handle.close
  end

  def file_path
    @grouping_group[:description_args].first.match(/(.+)\sRequests/)
    file_name = Regexp.last_match(1).gsub(' ', '').underscore

    "#{api_docs_folder_path}#{file_name}_blueprint.md"
  end

  def write_resource_to_file
    return if @@actions_covered.key?(resource)

    @@actions_covered["#{resource}"] = []

    @handle.write "## #{resource_description} [#{resource}]"
    @handle.write("\n")
  end

  def write_action_to_file
    return if @@actions_covered["#{resource}"].include?(action)

    @@actions_covered["#{resource}"] << action

    @handle.write "### #{action_description} [#{action}]"

    query_strings = URI.decode(request.env['QUERY_STRING']).split('&')

    @handle.write("\n")
    write_request_to_file
    write_response_to_file
  end

  def write_request_to_file
    request_body = request.body.read

    current_env  = request.env ? request.env : request.headers

    authorization_header = current_env['HTTP_AUTHORIZATION'] || env['X-HTTP_AUTHORIZATION'] ||
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
        header = header.gsub(/CONTENT_TYPE/, 'CONTENT-TYPE') if header == 'CONTENT_TYPE'
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

  def write_response_to_file
    @handle.write "+ Response #{response.status} (#{response.content_type}; charset=#{response.charset})\n\n"

    if response.body.present? && response.content_type.to_s =~ /application\/json/
      @handle.write "#{JSON.pretty_generate(JSON.parse(response.body))}\n\n".indent(8)
    end
  end
end
