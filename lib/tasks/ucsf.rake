namespace :ucsf do
  task :sync => :environment do
    institution = Institution.find_by(name: 'UCSF')
    # scan new entries
    params = {}
    params['campus'] = 'SF'
    params['RunSearch'] = 'True'
    params['ShowDetail'] = 'False'
    params['SortASC'] = 'False'
    params['SortColumn'] = 'NCDId'
    params['TechCategories'] = '106'

    h = 'https://techtransfer.universityofcalifornia.edu/Default.aspx'

    agent = Mechanize.new
    page = agent.get h, params

    current_page = page.search('span[id="ctl00_ContentPlaceHolder1_ucNCDList_ucPagination_lblCurrentPageNum"]').text.to_i
    total_pages = page.search('span[id="ctl00_ContentPlaceHolder1_ucNCDList_ucPagination_lblTotalPages"]').text.to_i
    while true do
      patent_links = page.links_with(class: 'tech-link')   
      patent_links.each do |patent_link|
        # looking if patent is already in our db
        ref = patent_link.href.scan(/\d+/).first.to_i
        unless PatentEntry.where(ref: ref, institution: institution).any?
          PatentEntry.create(
            ref: ref,
            institution: institution 
          )
        end
      end
      # going to next page
      current_page += 1 
      break if current_page > total_pages 
      f = page.forms.first
      f.send('ctl00$ContentPlaceHolder1$ucNCDList$ucPagination$txtPageNumber='.to_sym, current_page)
      page = agent.submit(f, f.buttons[2])
    end
  end

  task :scrape => :environment do
    institution = Institution.find_by(name: 'UCSF')
    PatentEntry
      .where(state: 'new', institution: institution)
      .each do |patent_entry|
        scraper = ::PatentDatumScraper::Base.new
        raw_data = scraper.scrape_ucsf(patent_entry.ref)
        patent_entry.patent_raw.destroy if patent_entry.patent_raw.present? # destroy old result if present
        patent_raw = patent_entry.create_patent_raw(raw_data: raw_data)
        patent_entry.scrape! if patent_raw.valid?
      end
  end
end
