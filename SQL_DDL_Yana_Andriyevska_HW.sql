--CREATE DATABASE hotel_booking_db ; 
-- must be commented out after first run, otherwise the second run fails.

CREATE SCHEMA IF NOT EXISTS hotel_booking_system ;
SET search_path TO hotel_booking_system ;


CREATE TABLE IF NOT EXISTS "Guests" (
	"guest_id" INTEGER NOT NULL GENERATED ALWAYS AS IDENTITY,
	"guest_name" VARCHAR(255) NOT NULL,
	"g_phone" VARCHAR(15) NOT NULL CONSTRAINT chk_phone CHECK (g_phone ~ '^\+[1-9]\d{1,13}$'), --standart global phone format, with + so have to be varchar and not number
	"g_document_number" VARCHAR(50), --can contain letters like in passport number
	"g_document_type" VARCHAR(50) CONSTRAINT chk_doc_type CHECK (g_document_type IN ('id', 'passport', 'driver license')), -- allows only several document types
	"g_email" VARCHAR(255),
	"g_created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(), --default current time with adding new guest
	PRIMARY KEY("guest_id"),
	CONSTRAINT "chk_guests_unique_0" UNIQUE ("g_document_number", "g_document_type") --can be only one unique number for each type of document
);


CREATE TABLE IF NOT EXISTS "Employees" (
	"employee_id" INTEGER NOT NULL GENERATED ALWAYS AS IDENTITY,
	"employee_name" VARCHAR(255) NOT NULL,
	"hotel_id" INTEGER NOT NULL,
	"manager_id" INTEGER CHECK (manager_id <> employee_id), -- employee can't be manager for himself
	PRIMARY KEY("employee_id")
);


CREATE TABLE IF NOT EXISTS "Hotels" (
	"hotel_id" INTEGER NOT NULL GENERATED ALWAYS AS IDENTITY,
	"hotel_name" VARCHAR(100) NOT NULL,
	"hotel_address" VARCHAR(255) NOT NULL,
	PRIMARY KEY("hotel_id")
);

CREATE TABLE IF NOT EXISTS "Rooms" (
	"room_id" INTEGER NOT NULL GENERATED ALWAYS AS IDENTITY,
	"room_number" INTEGER NOT NULL,
	"hotel_id" INTEGER NOT NULL,
	"r_basic_capacity" INTEGER NOT NULL CHECK ("r_basic_capacity" >= 1), --basic capacity must be one or more, constraint to avoid errors
	"r_additional_capacity" INTEGER NOT NULL DEFAULT 0 CHECK ("r_additional_capacity" >= 0), --can't be negative number
	"r_bed_type" VARCHAR(50) NOT NULL CONSTRAINT chk_bed_type CHECK (r_bed_type IN ('single', 'double', 'both')), -- allows only several bed types for future filtering
	"r_view" BOOLEAN NOT NULL,
	"r_jacuzzi" BOOLEAN NOT NULL,
	PRIMARY KEY("room_id"),
	CONSTRAINT "chk_rooms_unique_0" UNIQUE ("hotel_id", "room_number") --in one hotel can't be room with the same number, but in different can
);

CREATE TABLE IF NOT EXISTS "Room_pricing_changes" (
	"room_id" INTEGER NOT NULL,
	"r_price_valid_from" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	-- current price's date_till is 01/01/2099
	"r_price_valid_till" TIMESTAMPTZ NOT NULL DEFAULT '2099-01-01 00:00:00+00', --default date is maximum to avoid termination before it is nessesary
	"r_basic_price" NUMERIC(10,2) NOT NULL CHECK ("r_basic_price" >= 0), --blocks negative prices (typos, import errors)
	"r_additional_guest_price" NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK ("r_additional_guest_price" >= 0), --preserve from nulls and negative numbers for consistent future calculations
	"r_high_season_rate" NUMERIC(3,2) NOT NULL DEFAULT 1, --gives some flexibility, rate can be 1.30 or 2.00 for example
	"r_weekend_rate" NUMERIC(3,2) NOT NULL DEFAULT 1,
	PRIMARY KEY("room_id", "r_price_valid_from"), --because one room can change it price several times
	CONSTRAINT chk_r_price_date CHECK (r_price_valid_till > r_price_valid_from) --start date must be before end date
);

CREATE OR REPLACE FUNCTION room_price_before_insert() RETURNS trigger AS $$
BEGIN
    -- 1) close current price
    IF NEW."r_price_valid_till" = '2099-01-01 00:00:00+00' THEN
        UPDATE "Room_pricing_changes"
        SET    "r_price_valid_till" = NEW."r_price_valid_from"
        WHERE  "room_id" = NEW."room_id"
          AND  "r_price_valid_till" = '2099-01-01 00:00:00+00'
          AND  "r_price_valid_from" < NEW."r_price_valid_from";
    END IF;

    -- 2) check dates overlapping
    IF EXISTS (
        SELECT 1 FROM "Room_pricing_changes" p
        WHERE  p."room_id" = NEW."room_id"
          AND  p."r_price_valid_from" < NEW."r_price_valid_till"
          AND  NEW."r_price_valid_from" < p."r_price_valid_till"
    ) THEN
        RAISE EXCEPTION 'Price period % - % overlaps an existing price of room %',
              NEW."r_price_valid_from", NEW."r_price_valid_till", NEW."room_id";
    END IF;
    RETURN NEW;
END;

$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_room_price_before_insert ON "Room_pricing_changes";

CREATE TRIGGER trg_room_price_before_insert
BEFORE INSERT ON "Room_pricing_changes"
FOR EACH ROW EXECUTE FUNCTION room_price_before_insert();

-- The trigger syntax is a draft, as we have not covered triggers in the course yet. 
-- However, since it is requested that I implement this logic, I have tried to do so.


COMMENT ON COLUMN "Room_pricing_changes"."r_price_valid_till" IS 'current price''s date_till is 01/01/2099';


CREATE TABLE IF NOT EXISTS "Services" (
	"service_id" INTEGER NOT NULL GENERATED ALWAYS AS IDENTITY,
	"service_name" VARCHAR(100) NOT NULL,
	PRIMARY KEY("service_id")
);


CREATE TABLE IF NOT EXISTS "Booking_status" (
	"booking_status_id" INTEGER NOT NULL GENERATED ALWAYS AS IDENTITY,
	"booking_status_name" VARCHAR(100) NOT NULL,
	PRIMARY KEY("booking_status_id")
);


CREATE TABLE IF NOT EXISTS "Bookings" (
	"booking_id" BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY,
	"b_created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(), --in global time datatype because hotel may receive bookings from another countries
	-- this fields has impact on view that shows rooms availability
	"b_stay_from" TIMESTAMPTZ NOT NULL CHECK ("b_stay_from" > '2000-01-01 00:00:00+00'::TIMESTAMPTZ),
	-- this fields has impact on view that shows rooms availability
	"b_stay_till" TIMESTAMPTZ NOT NULL,
	"guest_id" INTEGER NOT NULL, --booking must have guest
	"is_prepaid" BOOLEAN NOT NULL,
	"b_handled_by" INTEGER NOT NULL, --booking must have employee that handled it
	PRIMARY KEY("booking_id"),
	CONSTRAINT chk_stay_date CHECK (b_stay_till > b_stay_from) --start date must be before end date, otherwise will be error
);


CREATE TABLE IF NOT EXISTS "Booking_details" (
	"booking_id" BIGINT NOT NULL,
	-- this fields has impact on view that shows rooms availability
	"room_id" INTEGER NOT NULL, --need for future total cost calculation 
	"guests_number" INTEGER NOT NULL, --need for future total cost calculation 
	PRIMARY KEY("booking_id", "room_id")
);

/*
Double-booking of the same room is not prevented by a constraint, because room_id (Booking_details) and stay dates (Bookings) are in different tables.
Availability is checked through the view Room_occupied_periods.
A possible future improvement to check room availability that I discovered lately: a trigger on Booking_details that rejects overlapping stays for the same room.
EXCLUDE USING gist (
    "room_id" WITH =,
    tstzrange("b_stay_from", "b_stay_till", '[)') WITH &&
);
*/


CREATE TABLE IF NOT EXISTS "Booking_status_history" (
	"booking_id" BIGINT NOT NULL,
	"changed_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(), --now by default to track changing time
	"booking_status_id" INTEGER NOT NULL,
	PRIMARY KEY("booking_id", "changed_at") --same booking can't be changed simultaneosly several times, but can be changed twice or more times in general
);

CREATE TABLE IF NOT EXISTS "Booking_services" (
	"booking_id" BIGINT NOT NULL,
	"service_id" INTEGER NOT NULL,
	"s_handled_by" INTEGER,
	"s_quantity" INTEGER NOT NULL CHECK ("s_quantity" > 0), --blocks negative quantities (typos, import errors)
	PRIMARY KEY("booking_id", "service_id")
);


-- availability check: rooms booked in a date range
CREATE OR REPLACE VIEW "Room_occupied_periods" AS
SELECT bd.room_id, r.hotel_id, r.room_number,
       b.booking_id, b.b_stay_from, b.b_stay_till
FROM   "Booking_details" bd
JOIN   "Bookings" b ON b.booking_id = bd.booking_id
JOIN   "Rooms"    r ON r.room_id    = bd.room_id
WHERE  (SELECT s.booking_status_name
        FROM   "Booking_status_history" h
        JOIN   "Booking_status" s ON s.booking_status_id = h.booking_status_id
        WHERE  h.booking_id = b.booking_id
        ORDER  BY h.changed_at DESC
        LIMIT  1) IS DISTINCT FROM 'cancelled'; --allows nulls if the booking is not in Booking_status_history table yet


CREATE TABLE IF NOT EXISTS "Customer_invoices" (
	"invoice_id" BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY,
	"inv_sum" NUMERIC(10,2) NOT NULL, --can be negative (flexibility for refunds)
	"discount" NUMERIC(3,2) NOT NULL DEFAULT 0, --discount can be negative and also bigger than 1 for flexibility
	"booking_id" BIGINT UNIQUE, -- one booking can have only one invoice, but we can issue an invoice for another services so booking_id can be null
	"cancelled_at" TIMESTAMPTZ CHECK ("cancelled_at" > '2000-01-01 00:00:00+00'::TIMESTAMPTZ),  --can be null because not every invoice is cancelled
	PRIMARY KEY("invoice_id")
);


CREATE TABLE IF NOT EXISTS "Customer_payments" (
	"receipt_id" BIGINT NOT NULL, --fills from a checkout system (cash desk)
	"payment_at" TIMESTAMPTZ NOT NULL CHECK ("payment_at" > '2000-01-01 00:00:00+00'::TIMESTAMPTZ), --fills from a checkout system (cash desk), CHECK prevent errors
	"invoice_id" BIGINT NOT NULL,
	"payment_method" VARCHAR(50) NOT NULL CONSTRAINT chk_pay_method CHECK (payment_method IN ('card', 'cash', 'other')), --only several types allowed for simplier searching and understanding by employees
	"payment_sum" NUMERIC(10,2) NOT NULL,
	"payment_status" VARCHAR(20) NOT NULL CHECK (payment_status IN ('pending','completed','failed','refunded')), --only several types allowed for simplier searching and understanding by employees
	PRIMARY KEY("receipt_id"),
	CONSTRAINT "chk_customer_payments_unique_0" UNIQUE ("payment_at", "invoice_id") --to avoid double payment and to see order of payments
);


CREATE TABLE IF NOT EXISTS "Additional_services_pricing" (
	"service_id" INTEGER NOT NULL,
	"s_price_valid_from" TIMESTAMPTZ NOT NULL DEFAULT NOW(), --to track changing time
	-- current price date_till is 01/01/2099
	"s_price_valid_till" TIMESTAMPTZ NOT NULL DEFAULT '2099-01-01 00:00:00+00', --date of current price is in the distant future to avoid overlapping
	"s_price" NUMERIC(10,2) NOT NULL CHECK ("s_price" >= 0), --blocks negative prices (typos, import errors)
	PRIMARY KEY("service_id", "s_price_valid_from"), --same as in room pricing
	CONSTRAINT chk_s_price_date CHECK (s_price_valid_till > s_price_valid_from) --same as in room pricing
);

CREATE OR REPLACE FUNCTION service_price_before_insert() RETURNS trigger AS $$
BEGIN
    -- 1) close current price
  IF NEW."s_price_valid_till" = '2099-01-01 00:00:00+00' THEN
        UPDATE "Additional_services_pricing"
        SET    "s_price_valid_till" = NEW."s_price_valid_from"
        WHERE  "service_id" = NEW."service_id"
          AND  "s_price_valid_till" = '2099-01-01 00:00:00+00'
          AND  "s_price_valid_from" < NEW."s_price_valid_from";
    END IF;

    -- 2) check dates overlapping
    IF EXISTS (
        SELECT 1 FROM "Additional_services_pricing" p
        WHERE  p."service_id" = NEW."service_id"
          AND  p."s_price_valid_from" < NEW."s_price_valid_till"
          AND  NEW."s_price_valid_from" < p."s_price_valid_till"
    ) THEN
        RAISE EXCEPTION 'Price period % - % overlaps an existing price of service %',
              NEW."s_price_valid_from", NEW."s_price_valid_till", NEW."service_id";
    END IF;
    RETURN NEW;
END;

$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_service_price_before_insert ON "Additional_services_pricing";

CREATE TRIGGER trg_service_price_before_insert
BEFORE INSERT ON "Additional_services_pricing"
FOR EACH ROW EXECUTE FUNCTION service_price_before_insert();

COMMENT ON COLUMN "Additional_services_pricing"."s_price_valid_till" IS 'current price date_till is 01/01/2099';


CREATE TABLE IF NOT EXISTS "Actual_stays" (
	"stay_id" BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY,
	"room_id" INTEGER NOT NULL,
	"booking_id" BIGINT NOT NULL,
	"check_in" TIMESTAMPTZ NOT NULL CHECK ("check_in" > '2000-01-01 00:00:00+00'::TIMESTAMPTZ), --check_in must be started to add row to the Actual_stays
	"check_out" TIMESTAMPTZ, --can be null for the current stays
	PRIMARY KEY("stay_id"),
	CONSTRAINT chk_in_out_date CHECK (check_out IS NULL OR check_out > check_in)
);

-- one open stay per room
CREATE UNIQUE INDEX IF NOT EXISTS uq_one_open_stay_per_room
  ON "Actual_stays" (room_id) WHERE check_out IS NULL; --we can't add stay to the room with no check_out time

-- indexes to speed up room availability check
-- IF NOT EXISTS: the script can be run again without errors
CREATE INDEX IF NOT EXISTS idx_booking_details_room ON "Booking_details" ("room_id");
CREATE INDEX IF NOT EXISTS idx_bookings_stay_dates  ON "Bookings" ("b_stay_from", "b_stay_till");


--Foreign keys (rerunnable)
--as was explained in the course theory, adding foreign keys after creating tables is better practice
--without FKs we could have bookings for non-existent guests or rooms, payments without invoice,
--a parent row could be deleted while child rows still use it
ALTER TABLE "Rooms" DROP CONSTRAINT IF EXISTS fk_rooms_hotels;
ALTER TABLE "Rooms"
    ADD CONSTRAINT fk_rooms_hotels
    FOREIGN KEY ("hotel_id") REFERENCES "Hotels" ("hotel_id")
    ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE "Employees" DROP CONSTRAINT IF EXISTS fk_employees_hotels;
ALTER TABLE "Employees"
    ADD CONSTRAINT fk_employees_hotels
    FOREIGN KEY ("hotel_id") REFERENCES "Hotels" ("hotel_id")
    ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE "Employees" DROP CONSTRAINT IF EXISTS fk_employees_manager;
ALTER TABLE "Employees"
    ADD CONSTRAINT fk_employees_manager
    FOREIGN KEY ("manager_id") REFERENCES "Employees" ("employee_id")
    ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE "Room_pricing_changes" DROP CONSTRAINT IF EXISTS fk_room_pricing_rooms;
ALTER TABLE "Room_pricing_changes"
    ADD CONSTRAINT fk_room_pricing_rooms
    FOREIGN KEY ("room_id") REFERENCES "Rooms" ("room_id")
    ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE "Bookings" DROP CONSTRAINT IF EXISTS fk_bookings_guests;
ALTER TABLE "Bookings"
    ADD CONSTRAINT fk_bookings_guests
    FOREIGN KEY ("guest_id") REFERENCES "Guests" ("guest_id")
    ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE "Bookings" DROP CONSTRAINT IF EXISTS fk_bookings_employees;
ALTER TABLE "Bookings"
    ADD CONSTRAINT fk_bookings_employees
    FOREIGN KEY ("b_handled_by") REFERENCES "Employees" ("employee_id")
    ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE "Booking_details" DROP CONSTRAINT IF EXISTS fk_booking_details_bookings;
ALTER TABLE "Booking_details"
    ADD CONSTRAINT fk_booking_details_bookings
    FOREIGN KEY ("booking_id") REFERENCES "Bookings" ("booking_id")
    ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE "Booking_details" DROP CONSTRAINT IF EXISTS fk_booking_details_rooms;
ALTER TABLE "Booking_details"
    ADD CONSTRAINT fk_booking_details_rooms
    FOREIGN KEY ("room_id") REFERENCES "Rooms" ("room_id")
    ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE "Booking_status_history" DROP CONSTRAINT IF EXISTS fk_status_history_bookings;
ALTER TABLE "Booking_status_history"
    ADD CONSTRAINT fk_status_history_bookings
    FOREIGN KEY ("booking_id") REFERENCES "Bookings" ("booking_id")
    ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE "Booking_status_history" DROP CONSTRAINT IF EXISTS fk_status_history_status;
ALTER TABLE "Booking_status_history"
    ADD CONSTRAINT fk_status_history_status
    FOREIGN KEY ("booking_status_id") REFERENCES "Booking_status" ("booking_status_id")
    ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE "Booking_services" DROP CONSTRAINT IF EXISTS fk_booking_services_bookings;
ALTER TABLE "Booking_services"
    ADD CONSTRAINT fk_booking_services_bookings
    FOREIGN KEY ("booking_id") REFERENCES "Bookings" ("booking_id")
    ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE "Booking_services" DROP CONSTRAINT IF EXISTS fk_booking_services_services;
ALTER TABLE "Booking_services"
    ADD CONSTRAINT fk_booking_services_services
    FOREIGN KEY ("service_id") REFERENCES "Services" ("service_id")
    ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE "Booking_services" DROP CONSTRAINT IF EXISTS fk_booking_services_employees;
ALTER TABLE "Booking_services"
    ADD CONSTRAINT fk_booking_services_employees
    FOREIGN KEY ("s_handled_by") REFERENCES "Employees" ("employee_id")
    ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE "Additional_services_pricing" DROP CONSTRAINT IF EXISTS fk_service_pricing_services;
ALTER TABLE "Additional_services_pricing"
    ADD CONSTRAINT fk_service_pricing_services
    FOREIGN KEY ("service_id") REFERENCES "Services" ("service_id")
    ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE "Customer_invoices" DROP CONSTRAINT IF EXISTS fk_invoices_bookings;
ALTER TABLE "Customer_invoices"
    ADD CONSTRAINT fk_invoices_bookings
    FOREIGN KEY ("booking_id") REFERENCES "Bookings" ("booking_id")
    ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE "Customer_payments" DROP CONSTRAINT IF EXISTS fk_payments_invoices;
ALTER TABLE "Customer_payments"
    ADD CONSTRAINT fk_payments_invoices
    FOREIGN KEY ("invoice_id") REFERENCES "Customer_invoices" ("invoice_id")
    ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE "Actual_stays" DROP CONSTRAINT IF EXISTS fk_actual_stays_bookings;
ALTER TABLE "Actual_stays"
    ADD CONSTRAINT fk_actual_stays_bookings
    FOREIGN KEY ("booking_id") REFERENCES "Bookings" ("booking_id")
    ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE "Actual_stays" DROP CONSTRAINT IF EXISTS fk_actual_stays_rooms;
ALTER TABLE "Actual_stays"
    ADD CONSTRAINT fk_actual_stays_rooms
    FOREIGN KEY ("room_id") REFERENCES "Rooms" ("room_id")
    ON UPDATE NO ACTION ON DELETE NO ACTION;





--Sample data 
-- Consistency and relationships:
--Identity columns (guest_id, booking_id, ...) are never typed in. Every foreign key value is looked up 
--by a business key (hotel name, room number, guest phone, employee name etc.) with JOINs, so a child row can only be created if its parent already exists.
--Tables are loaded parents first, children after (same order as the DDL).
--Rerunnable: 'WHERE NOT EXISTS' etc.

-- Hotels
INSERT INTO "Hotels" ("hotel_name", "hotel_address")
SELECT v.hotel_name, v.hotel_address
FROM (VALUES
        ('Harbor View Hotel', '12 Khreshchatyk Street, Kyiv'),
        ('Old Town Hotel',    '24 Rustaveli Street, Lviv')
     ) AS v(hotel_name, hotel_address)
WHERE NOT EXISTS (SELECT 1 FROM "Hotels" h WHERE h."hotel_name" = v.hotel_name);

-- Employees, step 1: employees without a manager
INSERT INTO "Employees" ("employee_name", "hotel_id", "manager_id")
SELECT v.employee_name, h."hotel_id", NULL
FROM (VALUES
        ('Maya Cohen', 'Harbor View Hotel'),
        ('Lior Barak', 'Old Town Hotel')
     ) AS v(employee_name, hotel_name)
JOIN "Hotels" h ON h."hotel_name" = v.hotel_name
WHERE NOT EXISTS (SELECT 1 FROM "Employees" e WHERE e."employee_name" = v.employee_name);

-- Employees, step 2: employees whose manager already exists (self-reference)
INSERT INTO "Employees" ("employee_name", "hotel_id", "manager_id")
SELECT v.employee_name, h."hotel_id", m."employee_id"
FROM (VALUES
        ('Omer Katz', 'Harbor View Hotel', 'Maya Cohen')
     ) AS v(employee_name, hotel_name, manager_name)
JOIN "Hotels"    h ON h."hotel_name"    = v.hotel_name
JOIN "Employees" m ON m."employee_name" = v.manager_name
WHERE NOT EXISTS (SELECT 1 FROM "Employees" e WHERE e."employee_name" = v.employee_name);

-- Guests (document is NULL for Tom, so the UNIQUE constraint cannot detect duplicates: WHERE NOT EXISTS on phone)
INSERT INTO "Guests" ("guest_name", "g_phone", "g_document_number", "g_document_type", "g_email", "g_created_at")
SELECT v.guest_name, v.g_phone, v.g_document_number, v.g_document_type, v.g_email, v.g_created_at::TIMESTAMPTZ
FROM (VALUES
        ('Anna Shevchenko', '+380501234567', 'AB123456', 'passport', 'anna@gmal.com', '2026-10-01 09:30:00+00'),
        ('Tom Brown',       '+972521112233', NULL,       NULL,       NULL,            '2026-10-05 16:40:00+00')
     ) AS v(guest_name, g_phone, g_document_number, g_document_type, g_email, g_created_at)
WHERE NOT EXISTS (SELECT 1 FROM "Guests" g WHERE g."g_phone" = v.g_phone);

-- Services
INSERT INTO "Services" ("service_name")
SELECT v.service_name
FROM (VALUES ('Breakfast'), ('Parking'), ('Spa access')) AS v(service_name)
WHERE NOT EXISTS (SELECT 1 FROM "Services" s WHERE s."service_name" = v.service_name);

-- Booking statuses (the view Room_occupied_periods depends on the name 'cancelled')
INSERT INTO "Booking_status" ("booking_status_name")
SELECT v.booking_status_name
FROM (VALUES ('pending'), ('confirmed'), ('cancelled'), ('completed')) AS v(booking_status_name)
WHERE NOT EXISTS (SELECT 1 FROM "Booking_status" s WHERE s."booking_status_name" = v.booking_status_name);

-- Rooms (alternative key: hotel + room number)
INSERT INTO "Rooms" ("room_number", "hotel_id", "r_basic_capacity", "r_additional_capacity",
                     "r_bed_type", "r_view", "r_jacuzzi")
SELECT v.room_number, h."hotel_id", v.basic_cap, v.add_cap, v.bed_type, v.has_view, v.has_jacuzzi
FROM (VALUES
        (101, 'Harbor View Hotel', 2, 1, 'double', TRUE,  FALSE),
        (102, 'Harbor View Hotel', 1, 0, 'single', FALSE, FALSE),
        (101, 'Old Town Hotel',    3, 1, 'both',   TRUE,  TRUE)
     ) AS v(room_number, hotel_name, basic_cap, add_cap, bed_type, has_view, has_jacuzzi)
JOIN "Hotels" h ON h."hotel_name" = v.hotel_name
ON CONFLICT ("hotel_id", "room_number") DO NOTHING;

-- Room prices: WHERE NOT EXISTS, because the BEFORE INSERT trigger runs before ON CONFLICT is checked.
-- Explicit valid_till is given for closed periods; the current price uses the 2099 default.
INSERT INTO "Room_pricing_changes" ("room_id", "r_price_valid_from", "r_price_valid_till", "r_basic_price",
                                    "r_additional_guest_price", "r_high_season_rate", "r_weekend_rate")
SELECT r."room_id", v.valid_from::TIMESTAMPTZ, v.valid_till::TIMESTAMPTZ,
       v.basic_price::NUMERIC, v.add_price::NUMERIC, v.high_rate::NUMERIC, v.weekend_rate::NUMERIC
FROM (VALUES
        (101, 'Harbor View Hotel', '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00', '300.00', '50.00', '1.25', '1.10'),
        (101, 'Harbor View Hotel', '2026-07-01 00:00:00+00', '2099-01-01 00:00:00+00', '340.00', '50.00', '1.25', '1.10'),
        (102, 'Harbor View Hotel', '2026-01-01 00:00:00+00', '2099-01-01 00:00:00+00', '220.00', '0.00',  '1.20', '1.00')
     ) AS v(room_number, hotel_name, valid_from, valid_till, basic_price, add_price, high_rate, weekend_rate)
JOIN "Hotels" h ON h."hotel_name" = v.hotel_name
JOIN "Rooms"  r ON r."hotel_id" = h."hotel_id" AND r."room_number" = v.room_number
WHERE NOT EXISTS (SELECT 1 FROM "Room_pricing_changes" p
                  WHERE p."room_id" = r."room_id"
                    AND p."r_price_valid_from" = v.valid_from::TIMESTAMPTZ);

-- Service prices (same reason: trigger)
INSERT INTO "Additional_services_pricing" ("service_id", "s_price_valid_from", "s_price_valid_till", "s_price")
SELECT s."service_id", v.valid_from::TIMESTAMPTZ, v.valid_till::TIMESTAMPTZ, v.price::NUMERIC
FROM (VALUES
        ('Breakfast',  '2026-01-01 00:00:00+00', '2026-09-01 00:00:00+00', '45.00'),
        ('Breakfast',  '2026-09-01 00:00:00+00', '2099-01-01 00:00:00+00', '50.00'),
        ('Parking',    '2026-01-01 00:00:00+00', '2099-01-01 00:00:00+00', '30.00'),
        ('Spa access', '2026-01-01 00:00:00+00', '2099-01-01 00:00:00+00', '120.00')
     ) AS v(service_name, valid_from, valid_till, price)
JOIN "Services" s ON s."service_name" = v.service_name
WHERE NOT EXISTS (SELECT 1 FROM "Additional_services_pricing" p
                  WHERE p."service_id" = s."service_id"
                    AND p."s_price_valid_from" = v.valid_from::TIMESTAMPTZ);

-- Bookings (no natural key: a guest cannot start two bookings at the same moment -> WHERE NOT EXISTS)
INSERT INTO "Bookings" ("b_created_at", "b_stay_from", "b_stay_till", "guest_id", "is_prepaid", "b_handled_by")
SELECT v.created_at::TIMESTAMPTZ, v.stay_from::TIMESTAMPTZ, v.stay_till::TIMESTAMPTZ,
       g."guest_id", v.is_prepaid, e."employee_id"
FROM (VALUES
        ('2026-10-01 09:30:00+00', '2026-11-10 14:00:00+00', '2026-11-13 11:00:00+00', '+380501234567', FALSE, 'Omer Katz'),
        ('2026-10-05 16:45:00+00', '2026-11-11 14:00:00+00', '2026-11-12 11:00:00+00', '+972521112233', TRUE,  'Lior Barak'),
        ('2026-10-04 10:15:00+00', '2026-10-20 14:00:00+00', '2026-10-22 11:00:00+00', '+380501234567', FALSE, 'Omer Katz')
     ) AS v(created_at, stay_from, stay_till, phone, is_prepaid, employee_name)
JOIN "Guests"    g ON g."g_phone"       = v.phone
JOIN "Employees" e ON e."employee_name" = v.employee_name
WHERE NOT EXISTS (SELECT 1 FROM "Bookings" b
                  WHERE b."guest_id" = g."guest_id"
                    AND b."b_stay_from" = v.stay_from::TIMESTAMPTZ);

-- Booking details (PK: booking + room)
INSERT INTO "Booking_details" ("booking_id", "room_id", "guests_number")
SELECT b."booking_id", r."room_id", v.guests_number
FROM (VALUES
        ('+380501234567', '2026-11-10 14:00:00+00', 'Harbor View Hotel', 101, 2),
        ('+380501234567', '2026-11-10 14:00:00+00', 'Harbor View Hotel', 102, 1),
        ('+972521112233', '2026-11-11 14:00:00+00', 'Old Town Hotel',    101, 3),
        ('+380501234567', '2026-10-20 14:00:00+00', 'Harbor View Hotel', 101, 2)
     ) AS v(phone, stay_from, hotel_name, room_number, guests_number)
JOIN "Guests"   g ON g."g_phone" = v.phone
JOIN "Bookings" b ON b."guest_id" = g."guest_id" AND b."b_stay_from" = v.stay_from::TIMESTAMPTZ
JOIN "Hotels"   h ON h."hotel_name" = v.hotel_name
JOIN "Rooms"    r ON r."hotel_id" = h."hotel_id" AND r."room_number" = v.room_number
ON CONFLICT ("booking_id", "room_id") DO NOTHING;

-- Booking status history (PK: booking + changed_at)
INSERT INTO "Booking_status_history" ("booking_id", "changed_at", "booking_status_id")
SELECT b."booking_id", v.changed_at::TIMESTAMPTZ, s."booking_status_id"
FROM (VALUES
        ('+380501234567', '2026-11-10 14:00:00+00', '2026-10-01 09:30:00+00', 'pending'),
        ('+380501234567', '2026-11-10 14:00:00+00', '2026-10-01 11:05:00+00', 'confirmed'),
        ('+972521112233', '2026-11-11 14:00:00+00', '2026-10-05 16:45:00+00', 'pending'),
        ('+972521112233', '2026-11-11 14:00:00+00', '2026-10-05 17:10:00+00', 'confirmed'),
        ('+972521112233', '2026-11-11 14:00:00+00', '2026-10-20 09:00:00+00', 'cancelled'),
        ('+972521112233', '2026-11-11 14:00:00+00', '2026-10-21 12:00:00+00', 'confirmed'),
        ('+380501234567', '2026-10-20 14:00:00+00', '2026-10-04 10:15:00+00', 'pending'),
        ('+380501234567', '2026-10-20 14:00:00+00', '2026-10-04 10:20:00+00', 'confirmed'),
        ('+380501234567', '2026-10-20 14:00:00+00', '2026-10-06 12:13:00+00', 'cancelled')
     ) AS v(phone, stay_from, changed_at, status_name)
JOIN "Guests"         g ON g."g_phone" = v.phone
JOIN "Bookings"       b ON b."guest_id" = g."guest_id" AND b."b_stay_from" = v.stay_from::TIMESTAMPTZ
JOIN "Booking_status" s ON s."booking_status_name" = v.status_name
ON CONFLICT ("booking_id", "changed_at") DO NOTHING;

-- Booking services (s_handled_by is optional -> LEFT JOIN keeps the row with NULL)
INSERT INTO "Booking_services" ("booking_id", "service_id", "s_handled_by", "s_quantity")
SELECT b."booking_id", s."service_id", e."employee_id", v.quantity
FROM (VALUES
        ('+380501234567', '2026-11-10 14:00:00+00', 'Breakfast',  'Omer Katz', 3),
        ('+380501234567', '2026-11-10 14:00:00+00', 'Parking',    NULL,        1),
        ('+972521112233', '2026-11-11 14:00:00+00', 'Spa access', 'Lior Barak', 2)
     ) AS v(phone, stay_from, service_name, employee_name, quantity)
JOIN "Guests"   g ON g."g_phone" = v.phone
JOIN "Bookings" b ON b."guest_id" = g."guest_id" AND b."b_stay_from" = v.stay_from::TIMESTAMPTZ
JOIN "Services" s ON s."service_name" = v.service_name
LEFT JOIN "Employees" e ON e."employee_name" = v.employee_name
ON CONFLICT ("booking_id", "service_id") DO NOTHING;

-- Customer invoices. Invoice 3 has no booking (additional bills), so booking_id is NULL and the UNIQUE
-- constraint cannot detect a duplicate: WHERE NOT EXISTS with IS NOT DISTINCT FROM.
INSERT INTO "Customer_invoices" ("inv_sum", "discount", "booking_id", "cancelled_at")
SELECT v.inv_sum::NUMERIC, v.discount::NUMERIC, b."booking_id", v.cancelled_at::TIMESTAMPTZ
FROM (VALUES
        ('1450.00', '0.10', '+380501234567', '2026-11-10 14:00:00+00', NULL),
        ('380.00',  '0.00', '+972521112233', '2026-11-11 14:00:00+00', NULL),
        ('85.00',   '0.00', NULL,            NULL,                     NULL),
        ('350.00',  '0.00', '+380501234567', '2026-10-20 14:00:00+00', '2026-10-06 12:13:00+00')
     ) AS v(inv_sum, discount, phone, stay_from, cancelled_at)
LEFT JOIN "Guests"   g ON g."g_phone" = v.phone
LEFT JOIN "Bookings" b ON b."guest_id" = g."guest_id" AND b."b_stay_from" = v.stay_from::TIMESTAMPTZ
WHERE NOT EXISTS (SELECT 1 FROM "Customer_invoices" i
                  WHERE i."inv_sum" = v.inv_sum::NUMERIC
                    AND i."booking_id" IS NOT DISTINCT FROM b."booking_id");

-- Customer payments. receipt_id and payment_at come from the external payment system (see description),
-- so receipt_id is given explicitly and is the conflict target. The invoice is found by amount + booking.
INSERT INTO "Customer_payments" ("receipt_id", "payment_at", "invoice_id", "payment_method", "payment_sum", "payment_status")
SELECT v.receipt_id, v.payment_at::TIMESTAMPTZ, i."invoice_id", v.payment_method, v.payment_sum::NUMERIC, v.payment_status
FROM (VALUES
        (1, '2026-10-01 11:10:00+00', '1450.00', '+380501234567', '2026-11-10 14:00:00+00', 'card', '500.00', 'completed'),
        (2, '2026-10-05 16:50:00+00', '380.00',  '+972521112233', '2026-11-11 14:00:00+00', 'card', '380.00', 'completed'),
        (3, '2026-11-11 19:20:00+00', '85.00',   NULL,            NULL,                     'card', '85.00',  'completed'),
        (4, '2026-11-13 10:45:00+00', '1450.00', '+380501234567', '2026-11-10 14:00:00+00', 'card', '805.00', 'failed'),
        (5, '2026-11-13 10:47:00+00', '1450.00', '+380501234567', '2026-11-10 14:00:00+00', 'cash', '805.00', 'completed')
     ) AS v(receipt_id, payment_at, inv_sum, phone, stay_from, payment_method, payment_sum, payment_status)
LEFT JOIN "Guests"   g ON g."g_phone" = v.phone
LEFT JOIN "Bookings" b ON b."guest_id" = g."guest_id" AND b."b_stay_from" = v.stay_from::TIMESTAMPTZ
JOIN "Customer_invoices" i ON i."inv_sum" = v.inv_sum::NUMERIC
                          AND i."booking_id" IS NOT DISTINCT FROM b."booking_id"
ON CONFLICT ("receipt_id") DO NOTHING;

-- Actual stays (stay 3 is still open: check_out IS NULL)
INSERT INTO "Actual_stays" ("room_id", "booking_id", "check_in", "check_out")
SELECT r."room_id", b."booking_id", v.check_in::TIMESTAMPTZ, v.check_out::TIMESTAMPTZ
FROM (VALUES
        ('Harbor View Hotel', 101, '+380501234567', '2026-11-10 14:00:00+00', '2026-11-10 14:20:00+00', '2026-11-13 10:40:00+00'),
        ('Harbor View Hotel', 102, '+380501234567', '2026-11-10 14:00:00+00', '2026-11-10 14:35:00+00', '2026-11-13 10:42:00+00'),
        ('Old Town Hotel',    101, '+972521112233', '2026-11-11 14:00:00+00', '2026-11-11 15:00:00+00', NULL)
     ) AS v(hotel_name, room_number, phone, stay_from, check_in, check_out)
JOIN "Hotels"   h ON h."hotel_name" = v.hotel_name
JOIN "Rooms"    r ON r."hotel_id" = h."hotel_id" AND r."room_number" = v.room_number
JOIN "Guests"   g ON g."g_phone" = v.phone
JOIN "Bookings" b ON b."guest_id" = g."guest_id" AND b."b_stay_from" = v.stay_from::TIMESTAMPTZ
WHERE NOT EXISTS (SELECT 1 FROM "Actual_stays" a
                  WHERE a."booking_id" = b."booking_id"
                    AND a."room_id"    = r."room_id"
                    AND a."check_in"   = v.check_in::TIMESTAMPTZ);