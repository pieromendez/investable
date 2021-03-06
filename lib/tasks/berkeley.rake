namespace :berkeley do
  task :sync => :environment do
    institution = Institution.find_by(name: 'Berkeley')
    # scan new entries
    params = {}
    params['campus'] = 'BK'
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
    institution = Institution.find_by(name: 'Berkeley')
    scraper = ::PatentDatumScraper::Base.new
    PatentEntry
      .where(state: 'new', institution: institution)
      .each do |patent_entry|
        begin
          p 'Processing patent entry #%s' % patent_entry.id
          sleep 2+rand(10)/10.0
          raw_data = ::PatentUtils.remap scraper.scrape_berkley(patent_entry.ref)
          patent_entry.patent_raw.destroy if patent_entry.patent_raw.present? # destroy old result if present
          patent_raw = patent_entry.create_patent_raw(
            raw_data: raw_data,
            institution: patent_entry.institution
          )
          if patent_raw.valid?
            patent_entry.scrape!
          else
            Airbrake.notify_or_ignore(
              error_message: patent_raw.errors.full_messages.join('.')
            )
            patent_entry.cancel!
          end  
        rescue Exception => e
          patent_entry.cancel!
          ::ErrorReporter.report(e)
        end
      end
  end

  task :scrape_rebuild => :environment do
    institution = Institution.find_by(name: 'Berkeley')
    PatentEntry.where(institution: institution).map(&:retry!)
    Rake::Task["berkeley:scrape"].invoke
  end

  task :index => :environment do
    institution = Institution.find_by(name: 'Berkeley')
    PatentRaw
      .where(state: 'new', institution: institution)
      .each do |patent_raw|
        begin
          patent_index = ::PatentUtils.index(patent_raw: patent_raw)
          if patent_index.valid?
            patent_raw.converted!
          else
            Airbrake.notify_or_ignore(
              error_message: patent_index.errors.full_messages.join('.')
            )
            patent_raw.cancel!
          end  
        rescue Exception => e
          patent_raw.cancel!
          ::ErrorReporter.report(e)
        end
      end
  end

end
