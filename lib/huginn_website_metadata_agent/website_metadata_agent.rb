module Agents
  class WebsiteMetadataAgent < Agent
    include FormConfigurable

    can_dry_run!
    cannot_be_scheduled!
    no_bulk_receive!

    gem_dependency_check { defined?(Mida) }

    description <<-MD
      The WebsiteMetadata Agent extracts metadata from HTML. It supports schema.org microdata, embedded JSON-LD and the common meta tag attributes.

      #{'## Include `mida` in your Gemfile to use this Agent!' if dependencies_missing?}

      `data` HTML to use in the extraction process, use [Liquid](https://github.com/cantino/huginn/wiki/Formatting-Events-using-Liquid) formatting to select data from incoming events.

      `url` optionally set the source URL of the provided HTML (without an URL schema.org links can not be extracted properly)

      `result_key` sets the key which contains the the extracted information.

      `merge` set to true to retain the received payload and update it with the extracted result

      [Liquid](https://github.com/cantino/huginn/wiki/Formatting-Events-using-Liquid) formatting can be used in all options.
    MD

    event_description do
      event = Utils.pretty_print(interpolated['result_key'] => {'schemaorg' => {}, 'meta' => ''})
      "Events will looks like this:\n\n    #{event}"
    end

    def default_options
      {
        'data' => '{{body}}',
        'url' => '{{url}}',
        'merge' => 'false',
        'result_key' => 'data'
      }
    end

    form_configurable :data
    form_configurable :url
    form_configurable :merge, type: :boolean
    form_configurable :result_key

    def validate_options
      errors.add(:base, "data needs to be present") if  options['data'].blank?
    end

    def working?
      received_event_without_error?
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        mo = interpolated(event)

        doc = Mida::Document.new(mo['data'], mo['url'])

        payload = {meta: {}}

        payload[:schemaorg] = doc.items.map do |item|
          next if item.type.nil?
          (context, sep, type) = item.type.rpartition('/')
          handle_item(item, {"@context" => "#{rewrite_context(context)}#{sep}", '@type' => type})
        end.compact

        doc = Nokogiri::HTML(mo['data'])
        doc.css('script[type="application/ld+json"]').each do |el|
          begin
            payload[:schemaorg] << JSON.parse(el.text)
          rescue JSON::ParserError
            error("Unable to parse JSON-LD script tag: #{el.text}")
          end
        end

        doc.css("meta[name], meta[property]").each do |el|
          payload[:meta][(el.attr("name") || el.attr("property")).try(:strip)] = (el.attr("content") || el.attr("value")).try(:strip)
        end

        original_payload = boolify(mo['merge']) ? event.payload : {}

        create_event payload: original_payload.merge(mo['result_key'] => payload)
      end
    end

    private

    CONTEXT_MAP = { "http://data-vocabulary.org" => "http://schema.org" }

    def rewrite_context(context)
      CONTEXT_MAP[context] || context
    end

    def handle_item(item, hash = {"@type" => item.type})
      hash.tap do |i|
        item.properties.each do |key, value|
          i[key] = handle_value(value)
        end
      end
    end

    def handle_value(value)
      case value
      when String, Float, Integer
        value
      when Array
        handle_array(value)
      when Mida::Item
        handle_item(value)
      else
        error("Not able to handle value: #{value.inspect}")
        nil
      end
    end

    def handle_array(value)
      array = value.map do |v|
        handle_value(v)
      end
      array.length == 1 ? array.first : array
    end
  end
end
