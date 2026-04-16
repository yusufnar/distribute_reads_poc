module Api
  class DbInfoController < ApplicationController
    # GET /api/db_info
    # Uses distribute_reads to automatically route to replica
    # Falls back to primary when replication lag > 1 second
    def show
      result = distribute_reads(max_lag: 1, lag_failover: true) do
        db_info = ActiveRecord::Base.connection.execute(<<-SQL).first
          SELECT
            inet_server_addr() AS server_ip,
            inet_server_port() AS server_port,
            now() AS current_time,
            pg_is_in_recovery() AS is_replica,
            current_database() AS database_name,
            CASE
              WHEN pg_is_in_recovery() THEN
                EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp())
              ELSE
                0
            END AS replication_lag_seconds
        SQL
        db_info
      end

      render json: {
        server_ip: result["server_ip"],
        server_port: result["server_port"],
        current_time: result["current_time"],
        is_replica: result["is_replica"],
        database_name: result["database_name"],
        replication_lag_seconds: result["replication_lag_seconds"]&.to_f&.round(3),
        connected_to: result["is_replica"] ? "REPLICA" : "PRIMARY",
        distribute_reads_config: {
          max_lag: 1,
          lag_failover: true
        }
      }
    end

    # GET /api/db_info_all
    # Manually queries all 3 databases to show their status
    def show_all
      primary_info = query_database("pg-primary", 5432)
      replica1_info = query_database("pg-replica1", 5432)
      replica2_info = query_database("pg-replica2", 5432)

      # Also show where distribute_reads would route
      distribute_reads_result = distribute_reads(max_lag: 1, lag_failover: true) do
        ActiveRecord::Base.connection.execute(<<-SQL).first
          SELECT
            inet_server_addr() AS server_ip,
            pg_is_in_recovery() AS is_replica
        SQL
      end

      render json: {
        distribute_reads_routed_to: distribute_reads_result["is_replica"] ? "REPLICA" : "PRIMARY",
        distribute_reads_server_ip: distribute_reads_result["server_ip"],
        databases: {
          primary: primary_info,
          replica1: replica1_info,
          replica2: replica2_info
        }
      }
    end

    private

    def query_database(host, port)
      conn = PG.connect(host: host, port: port, dbname: "appdb", user: "postgres", password: "secret")
      result = conn.exec(<<-SQL).first
        SELECT
          inet_server_addr() AS server_ip,
          inet_server_port() AS server_port,
          now() AS current_time,
          pg_is_in_recovery() AS is_replica,
          CASE
            WHEN pg_is_in_recovery() THEN
              EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp())
            ELSE
              0
          END AS replication_lag_seconds
      SQL
      conn.close

      {
        host: host,
        server_ip: result["server_ip"],
        server_port: result["server_port"],
        current_time: result["current_time"],
        is_replica: result["is_replica"] == "t",
        replication_lag_seconds: result["replication_lag_seconds"]&.to_f&.round(3),
        status: result["is_replica"] == "t" ? "REPLICA" : "PRIMARY"
      }
    rescue => e
      { host: host, error: e.message, status: "UNREACHABLE" }
    end
  end
end
