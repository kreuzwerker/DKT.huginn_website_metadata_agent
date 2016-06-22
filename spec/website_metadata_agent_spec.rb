require 'rails_helper'
require 'huginn_agent/spec_helper'

describe Agents::WebsiteMetadataAgent do
  before(:each) do
    @checker = Agents::WebsiteMetadataAgent.new(:name => 'somename', :options => Agents::WebsiteMetadataAgent.new.default_options)
    @checker.user = users(:jane)
    @checker.save!
  end

  it 'renders the event description without errors' do
    expect { @checker.event_description }.not_to raise_error
  end

  context '#validate_options' do
    it 'is valid with the default options' do
      expect(@checker).to be_valid
    end

    it 'requires data to be set' do
      @checker.options['data'] = ""
      expect(@checker).not_to be_valid
    end
  end

  def read_file(name)
    File.read((File.join(File.dirname(__FILE__), "data_fixtures/", name)))
  end

  context '#receive' do
    it "should extract both embedded microdata and JSON-LD" do
      event = Event.new(payload: {"url" => "http://test.org", "body" => read_file("ebay.html") })
      expect { @checker.receive([event]) }.to change(Event, :count).by(1)
      event = Event.last
      schemaorg = event.payload[:data][:schemaorg]

      expect(schemaorg.length).to eq(3)
      expect(schemaorg.first).to eq({"@context"=>"http://schema.org/", "@type"=>"Breadcrumb", "url"=>["http://test.org/", "http://test.org/s-auto-rad-boot/c210", "http://test.org/s-autos/c216"], "title"=>["Kleinanzeigen", "Auto, Rad & Boot", "Autos"]})
      expect(schemaorg.last).to eq({"@context"=>"http://schema.org", "@type"=>"WebSite", "name"=>"eBay Kleinanzeigen", "url"=>"https://www.ebay-kleinanzeigen.de"})
    end

    it "extracts information from meta tags" do
      event = Event.new(payload: {"url" => "http://test.org", "body" => read_file("sz.html")})

      expect { @checker.receive([event]) }.to change(Event, :count).by(1)
      event = Event.last
      expect(event.payload[:data][:schemaorg].length).to eq(1)
      expect(event.payload[:data][:meta]).to eq({"author"=>"Süddeutsche.de GmbH, Munich, Germany", "copyright"=>"Süddeutsche.de GmbH, Munich, Germany", "email"=>"kontakt@sueddeutsche.de", "description"=>"Hartz-IV: 750 000 Deutsche zwischen 15 und 24 sind auf Hartz-IV angewiesen. Und wer länger in dieser Situation ist, kommt schwer wieder raus.", "keywords"=>"Jugendarbeitslosigkeit, Arbeitslosigkeit, Wirtschaft, Süddeutsche Zeitung, SZ", "news_keywords"=>"Jugendarbeitslosigkeit, Arbeitslosigkeit, Wirtschaft", "robots"=>"index,follow,noarchive,noodp", "last-modified"=>"Mi, 11 Mai 2016 08:57:51 MESZ", "og:url"=>"http://www.sueddeutsche.de/wirtschaft/junge-hartz-iv-empfaenger-arm-im-wohlstandsland-1.2987303", "viewport"=>"width=1280", "twitter:card"=>"summary", "twitter:site"=>"@SZ", "og:type"=>"article", "og:title"=>"Junge Hartz-IV-Empfänger – Junge Menschen - gefangen im Hartz-IV-System", "og:description"=>"Fast 750 000 Deutsche zwischen 15 und 24 sind auf Hartz IV angewiesen. Wer länger in dieser Situation ist, kommt oft nur schwer wieder raus.", "og:image"=>"http://polpix.sueddeutsche.com/polopoly_fs/1.2987878.1462900090!/httpImage/image.jpg_gen/derivatives/940x528/image.jpg", "og:site_name"=>"Süddeutsche.de", "og:locale"=>"de_DE", "fb:app_id"=>"268419256515542", "fb:page_id"=>"26126004501", "apple-itunes-app"=>"app-id=338711072, app-argument=sdeapp://article/sz.1.2987303"})
    end

    it "works with a complex schema" do
      event = Event.new(payload: {"url" => "http://test.org", "body" => read_file('imdb.html')})
      expect { @checker.receive([event]) }.to change(AgentLog, :count).by(0)
    end

    it "creates an agent log entry when embedded JSON-LD is not parseable" do
      event = Event.new(payload: {"url" => "http://test.org", "body" => '<script type="application/ld+json">invalid JSON</script>'})
      expect { @checker.receive([event]) }.to change(AgentLog, :count).by(1)
    end

    it "merges the results with the received event when merge is set to true" do
      @checker.options['merge'] = "true"
      event = Event.new(payload: {"url" => "http://test.org", "body" => '<html></html>'})
      expect { @checker.receive([event]) }.to change(Event, :count).by(1)
      expect(Event.last.payload[:data][:url]).to be_present
    end
  end
end
