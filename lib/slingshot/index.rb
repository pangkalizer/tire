module Slingshot
  class Index

    def initialize(name, &block)
      @name = name
      instance_eval(&block) if block_given?
    end

    def delete
      # FIXME: RestClient does not return response for DELETE requests?
      @response = Configuration.client.delete "#{Configuration.url}/#{@name}"
      return @response =~ /error/ ? false : true
    rescue Exception => error
      false
    ensure
      curl = %Q|curl -X DELETE "#{Configuration.url}/#{@name}"|
      logged(error, 'DELETE', curl)
    end

    def create(options={})
      @options = options
      @response = Configuration.client.post "#{Configuration.url}/#{@name}", Yajl::Encoder.encode(options)
    rescue Exception => error
      false
    ensure
      curl = %Q|curl -X POST "#{Configuration.url}/#{@name}" -d '#{Yajl::Encoder.encode(options, :pretty => true)}'|
      logged(error, 'CREATE', curl)
    end

    def mapping
      JSON.parse( Configuration.client.get("#{Configuration.url}/#{@name}/_mapping") )[@name]
    end

    def store(*args)
      # TODO: Infer type from the document (hash property, method)

      if args.size > 1
        (type, document = args)
      else
        (document = args.pop; type = :document)
      end

      old_verbose, $VERBOSE = $VERBOSE, nil # Silence Object#id deprecation warnings
      id = case true
        when document.is_a?(Hash)                                           then document[:id] || document['id']
        when document.respond_to?(:id) && document.id != document.object_id then document.id
      end
      $VERBOSE = old_verbose

      document = case true
        when document.is_a?(String) then document
        when document.respond_to?(:to_indexed_json) then document.to_indexed_json
        else raise ArgumentError, "Please pass a JSON string or object with a 'to_indexed_json' method"
      end

      url = id ? "#{Configuration.url}/#{@name}/#{type}/#{id}" : "#{Configuration.url}/#{@name}/#{type}/"

      @response = Configuration.client.post url, document
      JSON.parse(@response)

    rescue Exception => error
      raise
    ensure
      curl = %Q|curl -X POST "#{url}" -d '#{document}'|
      logged(error, "/#{@name}/#{type}/", curl)
    end

    def retrieve(type, id)
      @response = Configuration.client.get "#{Configuration.url}/#{@name}/#{type}/#{id}"
      h = JSON.parse(@response)
      if Configuration.wrapper == Hash then h
      else
        document = h['_source'] ? h['_source'] : h['fields']
        h.update document if document
        Configuration.wrapper.new(h)
      end
    end

    def refresh
      @response = Configuration.client.post "#{Configuration.url}/#{@name}/_refresh", ''
    rescue Exception => error
      raise
    ensure
      curl = %Q|curl -X POST "#{Configuration.url}/#{@name}/_refresh"|
      logged(error, '_refresh', curl)
    end

    def logged(error=nil, endpoint='/', curl='')
      if Configuration.logger

        Configuration.logger.log_request endpoint, @name, curl

        code = @response ? @response.code : error.message rescue 200

        if Configuration.logger.level.to_s == 'debug'
          # FIXME: Depends on RestClient implementation
          body = @response ? Yajl::Encoder.encode(@response.body, :pretty => true) : error.http_body rescue ''
        else
          body = ''
        end

        Configuration.logger.log_response code, nil, body
      end
    end

  end
end
