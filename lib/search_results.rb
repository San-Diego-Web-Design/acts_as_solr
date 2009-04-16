module ActsAsSolr #:nodoc:
  
  # TODO: Possibly looking into hooking it up with Solr::Response::Standard
  # 
  # Class that returns the search results with four methods.
  # 
  #   books = Book.find_by_solr 'ruby'
  # 
  # the above will return a SearchResults class with 4 methods:
  # 
  # docs|results|records: will return an array of records found
  # 
  #   books.records.empty?
  #   => false
  # 
  # total|num_found|total_hits: will return the total number of records found
  # 
  #   books.total
  #   => 2
  # 
  # facets: will return the facets when doing a faceted search
  # 
  # max_score|highest_score: returns the highest score found
  # 
  #   books.max_score
  #   => 1.3213213
  # 
  # 
  class SearchResults
    def initialize(solr_data={})
      @solr_data = solr_data
    end
    
    # Returns an array with the instances. This method
    # is also aliased as docs and records
    def results
      @solr_data[:docs]
    end
    
    # Returns the total records found. This method is
    # also aliased as num_found and total_hits
    def total
      @solr_data[:total]
    end
    
    # Returns the facets when doing a faceted search
    def facets
      @solr_data[:facets]
    end
    
    # Returns the highest score found. This method is
    # also aliased as highest_score
    def max_score
      @solr_data[:max_score]
    end
    
    def query_time
      @solr_data[:query_time]
    end
   
    def offset
      @solr_data[:start]
    end

    def per_page
      @solr_data[:rows]
    end
    def current_page
      (offset / per_page).to_i + 1
    end
    def next_page
      current_page + 1 unless current_page == total_pages
    end
    def previous_page
      current_page - 1 unless current_page == 1
    end
    def total_pages
      total_pages = (total / per_page.to_f).ceil
      total_pages == 0 ? 1 : total_pages
    end

    def method_missing(method, *args, &block)
      results.send(method, *args, &block)
    end

    alias docs results
    alias records results
    alias num_found total
    alias total_hits total
    alias total_entries total
    alias highest_score max_score
  end
  
end