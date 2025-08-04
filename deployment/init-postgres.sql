-- PostgreSQL initialization script
-- Creates the dittofeed database if it doesn't exist

-- This script runs as the postgres superuser
SELECT 'CREATE DATABASE dittofeed'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'dittofeed')\gexec

-- Grant all privileges to the dittofeed user
GRANT ALL PRIVILEGES ON DATABASE dittofeed TO dittofeed;