-- =============================================================================
-- VexarDrive Fleet Ping Service — Database Schema
-- =============================================================================

-- Enable UUID extension (useful for future-proofing IDs)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Drivers table
CREATE TABLE IF NOT EXISTS drivers (
  id SERIAL PRIMARY KEY,
  phone VARCHAR(15) UNIQUE NOT NULL,
  name VARCHAR(100),
  otp_hash VARCHAR(255),          -- For OTP-based login (hashed, never plaintext)
  otp_expires_at TIMESTAMP,       -- OTP expiry time
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Add index for phone lookups (login uses phone)
CREATE INDEX IF NOT EXISTS idx_drivers_phone ON drivers(phone);

-- Fleet pings table
CREATE TABLE IF NOT EXISTS fleet_pings (
  id SERIAL PRIMARY KEY,
  vehicle_id VARCHAR(50) NOT NULL,
  lat DECIMAL(9,6),
  lng DECIMAL(9,6),
  speed DECIMAL(5,2),
  ts TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Index for vehicle lookups and time-range queries
CREATE INDEX IF NOT EXISTS idx_fleet_pings_vehicle_id ON fleet_pings(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_fleet_pings_ts ON fleet_pings(ts);
CREATE INDEX IF NOT EXISTS idx_fleet_pings_vehicle_ts ON fleet_pings(vehicle_id, ts);

-- Auto-update updated_at timestamp
-- a function that sets updated_at to the current time whenever a row is updated 
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attaches the function as a trigger to the drivers table
-- Ensures updated_at always reflects the last modification time automatically
CREATE TRIGGER trg_drivers_updated_at
  BEFORE UPDATE ON drivers
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();
