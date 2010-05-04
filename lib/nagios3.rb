################################################################################
# Author: Brian J Reath
# Date: April 7, 2010
#
# Copyright (c) CCI Systems, Inc. 2010
################################################################################
module Nagios3
  
  autoload :Contact,            'nagios3/contact'
  autoload :Host,               'nagios3/host'
  autoload :HostEscalation,     'nagios3/host_escalation'
  autoload :Service,            'nagios3/service'
  autoload :ServiceEscalation,  'nagios3/service_escalation'
  autoload :TimePeriod,         'nagios3/time_period'
  autoload :HostProcessor,      'nagios3/host_processor'
  autoload :ServiceProcessor,   'nagios3/service_processor'
  
  class << self
    attr_accessor :hosts_path, :services_path, :contacts_path
    attr_accessor :host_escalations_path, :service_escalations_path
    attr_accessor :time_periods_path
    
    attr_accessor :status_path, :object_path
    attr_accessor :host_perfdata_path, :service_perfdata_path
    attr_accessor :host_perfdata_url, :service_perfdata_url
    
    attr_accessor :pid_file
    
    def configure(&blk)
      yield(self)  
    end
  end
  
  class Nagios3Error < StandardError; end
  class DuplicateHostError < Nagios3Error; end
  class HostNotFoundError < Nagios3Error; end
  class DuplicateServiceError < Nagios3Error; end
  class ServiceNotFoundError < Nagios3Error; end
  class DuplicateContactError < Nagios3Error; end
  class ContactNotFoundError < Nagios3Error; end
  
end

if defined? Rails
  conf = YAML::load_file("#{Rails.root}/config/nagios3.yml")[Rails.env]
  
  Nagios3.configure do |c|
    c.hosts_path = conf['hosts_path']
    c.services_path = conf['services_path']
    c.contacts_path = contact['contacts_path']
    c.host_escalations_path = conf['host_escalations_path']
    c.service_escalations_path = conf['service_escalations_path']
    c.time_periods_path = conf['time_periods_path']
    c.status_path = conf['status_path']
    c.object_path = conf['object_path']
  end
end
