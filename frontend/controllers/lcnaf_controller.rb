require 'opensearcher'
require 'securerandom'

LOC_BASE     = (ENV['LCNAF_LOC_BASE_URL']&.chomp('/')) || 'https://id.loc.gov'
LOC_SEARCH   = "#{LOC_BASE}/search/"
LOC_NAMES    = "#{LOC_BASE}/authorities/names"
LOC_SUBJECTS = "#{LOC_BASE}/authorities/subjects"

class LcnafController < ApplicationController

  set_access_control "update_agent_record" => [:search, :index, :import]

  def index
    @page = 1
    @records_per_page = 10

    flash.now[:info] = I18n.t("plugins.lcnaf.messages.service_warning")
  end


  def search
    results = do_search(params)

    render :json => results.to_json
  end


  def import
    parse_results = searcher.results_to_marcxml_file(params[:lccn])

    begin
      # agents are processed by MarcXMLAuthAgentConverter introduced in ANW-429
      if parse_results[:agents][:count] > 0
        marcxml_file = parse_results[:agents][:file]

        import_subjects = params[:import_subjects] ? "1" : nil

        agents_job = Job.new("import_job", {
                             "import_type" => "marcxml_auth_agent",
                             "jsonmodel_type" => "import_job",
                             "import_subjects" => import_subjects
                            },
                      {"lcnaf_import_#{SecureRandom.uuid}" => marcxml_file})

        agents_job_response = agents_job.upload
      end

      # subjects are processed by MarcXMLBibConverter as before ANW-429
      if parse_results[:subjects][:count] > 0
        marcxml_file = parse_results[:subjects][:file]
        subjects_job = Job.new("import_job", {
                               "import_type" => "marcxml_subjects_and_agents",
                               "jsonmodel_type" => "import_job"
                              },
                      {"lcnaf_import_#{SecureRandom.uuid}" => marcxml_file})

        subjects_job_response = subjects_job.upload
      end

      # if only subjects or only agents are processed, forward user directly to the job show page.
      # if both subjects and agents are processed, then forward user to the jobs index page so they can see both
      if parse_results[:agents][:count] > 0 && parse_results[:subjects][:count] == 0
        render :json => {'job_uri' => url_for(:controller => :jobs, :action => :show, :id => agents_job_response['id'])}

      elsif parse_results[:agents][:count] == 0 && parse_results[:subjects][:count] > 0
        render :json => {'job_uri' => url_for(:controller => :jobs, :action => :show, :id => subjects_job_response['id'])}
      else
        render :json => {'job_uri' => url_for(:controller => :jobs, :action => :index)}
      end
         
    rescue
      render :json => {'error' => $!.to_s}
    end
  end


  private

  def do_search(params)
    searcher.search(params[:family_name], params[:page].to_i, params[:records_per_page].to_i)
  end


  def searcher
    case params[:lcnaf_service]
    when 'lcnaf'
      OpenSearcher.new(LOC_SEARCH, LOC_NAMES)
    when 'lcsh'
      OpenSearcher.new(LOC_SEARCH, LOC_SUBJECTS)
    end
  end
end
