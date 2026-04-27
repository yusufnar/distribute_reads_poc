# Distribute Reads PoC

This project is a Proof of Concept (PoC) demonstrating how to separate database read and write operations and distribute the read load across multiple replica servers (Load Balancing) in a Ruby on Rails application using the `distribute_reads` gem.

## Architecture

The system consists of one Primary PostgreSQL database and two connected Replica databases. The Rails application:
- Sends **Write** operations directly to the `pg-primary` server.
- Distributes **Read** operations to the `pg-replica1` and `pg-replica2` servers via a DNS alias named `pg-replicas` (using Round-Robin DNS Load Balancing).

### Workflow Flowchart (ASCII)

```text
                     +-----------------------+
                     |                       |
                     |       Rails App       |
                     |  (distribute_reads)   |
                     |                       |
                     +-----------+-----------+
                                 |
              +------------------+------------------+
              |                                     |
          [ Writes ]                             [ Reads ]
              |                                     |
              v                                     v
      +---------------+                     +---------------+
      |               |                     |  DNS Alias:   |
      |  pg-primary   |                     |  pg-replicas  |
      |               |                     +-------+-------+
      +-------+-------+                             |
              |                                     |
              | Streaming Replication               | Round Robin
              |                                     |  Routing
              |       +---------------+             |
              +------>|               |<------------+
                      |  pg-replica1  |             
              +------>|               |<------------+
              |       +---------------+             |
              |                                     |
              |       +---------------+             |
              +------>|               |<------------+
                      |  pg-replica2  |             
                      +---------------+             
```

## Contents and Directory Structure

- `docker-compose.yml`: The Docker environment containing the Rails application and the Primary/Replica databases.
- `/rails-app`: Contains the source code for the Rails API application.
- `/pg-primary`: Contains the initialization and configuration scripts for the Master PostgreSQL server.
- `/replica`: Contains the bash script used to initialize the Replica PostgreSQL servers.
- `*.sh` scripts: Various bash scripts necessary for monitoring replication status, stress testing the servers, and verifying the read load distribution (e.g., `check_replication.sh`, `stress_test_replicas.sh`, etc.).

## Getting Started

To spin up the project environment, you can use the following command:

```bash
docker compose up --build
```

With this command:
1. The database cluster (1 Primary, 2 Replicas) is created.
2. The Primary database sets up synchronization (Streaming Replication) with the Replicas.
3. The Rails application is started.
4. Load balancing is achieved across the replica databases via the `pg-replicas` address, thanks to Docker's internal DNS aliasing mechanism.