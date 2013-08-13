require 'net/http'
require 'json'

module Nagios3

  class ServiceProcessor
    def run
      perfdata, modems = parse_files
      load_to_database(perfdata, modems)
    end

    def send_noc
      perfdata, modems = get_from_database
      send_data(perfdata)
      send_modems(modems)
      delete_old_data
    end

  private
    def parse_files
      entries, perfdata, modems = perfdata_files, [], []
      entries.each do |entry|
        lines = File.readlines(entry)
        File.open(entry, "w") # clear file
        lines.each do |line|
          parsed_perfdata_line = parse(line)
          if parsed_perfdata_line[:id] == "modem"
            modems << parsed_perfdata_line
          else
            perfdata << parsed_perfdata_line
          end
        end
      end
      [perfdata, modems]
    end

    def load_to_database(perfdata,modems)
      perfdata.each do |p|
        run_sql(perfdata_sql(p))
      end
      modems.each do |m|
        run_sql(modem_sql(m))
      end
    end

    def perfdata_sql(hash)
      str = <<-SQL
        insert into host_service_perfdata values (DEFAULT, '#{Time.at(hash[:time].to_i)}',#{hash[:host_id] || "NULL"},
        '#{hash[:host]}','#{hash[:service]}','#{hash[:status]}','#{hash[:duration]}','#{hash[:execution_time]}',
        '#{hash[:latency]}','#{hash[:output]}','#{hash[:perfdata]}','#{DateTime.now.strftime("%Y-%m-%d %H:%M:%S")}', null)
SQL
    end

    def modem_sql(hash)
      str = <<-SQL
        insert into modem_service_perfdata values (DEFAULT, '#{Time.at(hash[:time].to_i)}',#{hash[:host_id] || "NULL"},
        '#{hash[:host]}','#{hash[:service]}','#{hash[:status]}','#{hash[:duration]}','#{hash[:execution_time]}',
        '#{hash[:latency]}','#{hash[:output]}','#{hash[:perfdata]}','#{DateTime.now.strftime("%Y-%m-%d %H:%M:%S")}', null)
SQL
    end

    def perfdata_files
      d = Dir.new(File.dirname(Nagios3.service_perfdata_path))
      entries = d.entries
      entries.delete_if { |entry| !(entry =~ /^service-perfdata/) }
      entries.map! { |entry| File.join(d.path, entry) }
      entries.sort
    end

    def get_from_database
      host_sql = "select id, EXTRACT(EPOCH FROM time)::int + 18000 AS time, host_id, host, service, status, duration, execution_time, latency, output, perfdata, created_at, sent_at from host_service_perfdata where sent_at is null order by created_at asc;"
      modem_sql = "select id, EXTRACT(EPOCH from time)::int + 18000 AS time, host_id, host, service, status, duration, execution_time,  latency, output, perfdata, created_at, sent_at from modem_service_perfdata where sent_at is null order by created_at asc;"
      result = [parse_sql_table(host_sql), parse_modem_sql_table(modem_sql)]
    end

    def parse_sql_table(sql)
      tbl = run_sql(sql)
      rows = tbl.split("\n")[2..-2]
      columns = tbl.split("\n")[0].split("|").each{|c|c.strip!}
      columns[columns.index("id")] = "table_id"
      columns[columns.index("host")] = "host_id"
      columns[columns.index("service")] = "id"
      result = []
      rows.each do |r|
        row = {}
        r.split("|").each_with_index do |v, i|
          row[columns[i].to_sym] = v.strip
        end
        if r =~ /[\w\d]+/
          result << row
        end
      end
      result
    end

    def parse_modem_sql_table(sql)
      tbl = run_sql(sql)
      rows = tbl.split("\n")[2..-2]
      columns = tbl.split("\n")[0].split("|").each{|c|c.strip!}
      columns[columns.index("id")] = "table_id"
      columns[columns.index("service")] = "id"
      result = []
      rows.each do |r|
        row = {}
        r.split("|").each_with_index do |v, i|
          row[columns[i].to_sym] = v.strip
        end
        if r =~ /[\w\d]+/
          result << row
        end
      end
      result
    end

    def mark_data(perfdata)
      if perfdata.count > 0
        ids = perfdata.inject([]){|sum, h| sum << h[:table_id]}.to_s.gsub!(/[\[\]]/,"")
        sql = "update host_service_perfdata set sent_at = '#{DateTime.now.strftime("%Y-%m-%d %H:%M:%S")}' where id in (#{ids})"
        run_sql(sql)
      end
    end

    def mark_modems(modems)
      if modems.count > 0
        ids = modems.inject([]){|sum, h| sum << h[:table_id]}.to_s.gsub!(/[\[\]]/,"")
        sql = "update modem_service_perfdata set sent_at = '#{DateTime.now.strftime("%Y-%m-%d %H:%M:%S")}' where id in (#{ids})"
        run_sql(sql)
      end
    end

    def send_data(perfdata)
      perfdata.in_groups_of(100, false) do |batch|
        push_request(Nagios3.service_perfdata_url, batch.to_json)
        mark_data(batch)
      end
    end

    def send_modems(modems)
      modems.in_groups_of(100, false) do |batch|
        push_request(Nagios3.modem_service_perfdata_url, batch.to_json)
        mark_modems(batch)
      end
    end

    def push_request(url, body)
      uri = URI.parse(url)
      headers = {
        'Content-Type' => 'application/json',
        'Content-Length' => body.size.to_s,
        'probe_identification' => get_probe_identifier
      }
      request = Net::HTTP::Post.new(uri.path, headers)
      http = Net::HTTP.new(uri.host, uri.port)
      timeout(5) do
        response = http.request(request, body)
      end
    end

    def delete_old_data
      sql = "delete from host_service_perfdata where created_at < '#{(DateTime.now-1.day).strftime("%Y-%m-%d %H:%M:%S")}'"
      run_sql(sql)
      sql = "delete from modem_service_perfdata where created_at < '#{(DateTime.now-1.day).strftime("%Y-%m-%d %H:%M:%S")}'"
      run_sql(sql)
    end

    def parse(line)
      if line =~ /^\[SERVICEPERFDATA\]([^\|]*)\|([^\|]*)\|([^\|]*)\|([^\|]*)\|([^\|]*)\|([^\|]*)\|([^\|]*)\|([^\|]*)\|([^\|]*)\|([^\|]*)$/
        perf_hash = {
          :time => $1, :id => $2, :host => $3, :service => $4, :status => $5,
          :duration => $6, :execution_time => $7, :latency => $8, :output => $9,
          :perfdata => $10
        }
      end
    end

    def run_sql(sql)
      sql.gsub!("\n", " ")
      `PGPASSWORD=mb723wk8 /usr/bin/psql -h localhost probe_production ccisystems -c "#{sql}"`
    end

    def get_probe_identifier  # Add this to the noc send command
      sql_return = `PGPASSWORD=mb723wk8 /usr/bin/psql -h localhost probe_production probe -c "select * from probe_identification_settings;"`
      sql_return.split("\n")[2].split(" | ")[1].strip
    end
  end

end
