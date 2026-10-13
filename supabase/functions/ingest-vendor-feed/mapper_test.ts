// Mirrors test/liftkit_vehicle_mapper_test.dart case for case. The two mappers
// normalize the same vocabulary for the same filter chips, so a divergence here
// is a bug even when both files individually look correct.
//
//   deno test supabase/functions/ingest-vendor-feed/mapper_test.ts

import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { mapRow, normalizeRow, pickDealerRef, SkippedRow } from "./mapper.ts";

const SOURCE = "vauto:48213";

function row(overrides: Record<string, string> = {}) {
  return normalizeRow({
    "Stock Number": "PG205293",
    VIN: "1FTFW1ET5DFA12345",
    Year: "2021",
    Make: "Ford",
    Model: "F-150",
    Trim: "Lariat",
    Mileage: "34,120",
    "Selling Price": "$45,995.00",
    ...overrides,
  });
}

Deno.test("maps a feed vehicle onto the app listing shape", () => {
  const v = mapRow(row(), SOURCE);

  assertEquals(v.source, SOURCE);
  assertEquals(v.external_id, "vauto:48213:PG205293");
  assertEquals(v.stock, "PG205293");
  assertEquals(v.vin, "1FTFW1ET5DFA12345");
  assertEquals(v.year, 2021);
  assertEquals(v.make, "Ford");
  assertEquals(v.model, "F-150");
  assertEquals(v.trim, "Lariat");
  assertEquals(v.mileage, 34120);
  assertEquals(v.price, 45995);
  assertEquals(v.promotion, null);
});

Deno.test("normalizes feed vocabulary to the app filter options", () => {
  const v = mapRow(
    row({
      "Body Style": "Crew Cab",
      "Fuel Type": "Unleaded",
      Transmission: "auto",
      Drivetrain: "Four Wheel Drive",
    }),
    SOURCE,
  );

  assertEquals(v.body, "Pickup Truck");
  assertEquals(v.fuel, "Gasoline");
  assertEquals(v.transmission, "Automatic");
});

Deno.test("promotes certified vehicles to their own status", () => {
  assertEquals(mapRow(row({ Condition: "Used" }), SOURCE).status, "Pre-Owned");
  assertEquals(mapRow(row({ Condition: "New" }), SOURCE).status, "New");
  assertEquals(
    mapRow(row({ Condition: "Used", Certified: "true" }), SOURCE).status,
    "Certified Pre-Owned",
  );
});

Deno.test("an unrecognised condition never becomes New", () => {
  assertEquals(
    mapRow(row({ Condition: "demo unit" }), SOURCE).status,
    "Pre-Owned",
  );
});

Deno.test("treats an SUV reported as a Wagon body as an SUV", () => {
  const v = mapRow(row({ "Body Style": "Wagon", Type: "SUV" }), SOURCE);
  assertEquals(v.body, "SUV");
});

Deno.test("strips HTML and entities out of the description", () => {
  const v = mapRow(
    row({ Description: "<p>Clean &amp; loaded</p><br/>One owner" }),
    SOURCE,
  );
  assertEquals(v.description, "Clean & loaded\nOne owner");
});

Deno.test("reads a discount as a promotional price", () => {
  const v = mapRow(
    row({ MSRP: "$52,000", "Internet Price": "$47,500" }),
    SOURCE,
  );
  assertEquals(v.price, 52000);
  assertEquals(v.promotion, 47500);
});

Deno.test("a sale price above list is not treated as a discount", () => {
  const v = mapRow(row({ MSRP: "$40,000", "Internet Price": "$42,000" }), SOURCE);
  assertEquals(v.price, 42000);
  assertEquals(v.promotion, null);
});

Deno.test('a missing price becomes zero, which the app shows as "Call for price"', () => {
  const v = mapRow(row({ "Selling Price": "" }), SOURCE);
  assertEquals(v.price, 0);
  assertEquals(v.promotion, null);
});

Deno.test("skips vehicles with no usable identity", () => {
  assertThrows(
    () => mapRow(row({ "Stock Number": "", VIN: "" }), SOURCE),
    SkippedRow,
  );
  assertThrows(() => mapRow(row({ Make: "", Model: "" }), SOURCE), SkippedRow);
});

Deno.test("falls back to the VIN when the feed omits a stock number", () => {
  const v = mapRow(row({ "Stock Number": "" }), SOURCE);
  assertEquals(v.stock, "1FTFW1ET5DFA12345");
  assertEquals(v.external_id, "vauto:48213:1FTFW1ET5DFA12345");
});

Deno.test("splits multi-value fields on the pipe we asked vAuto for", () => {
  const v = mapRow(
    row({ "Photo URLs": "https://a/1.jpg|https://a/2.jpg|https://a/3.jpg" }),
    SOURCE,
  );
  assertEquals(v.images, "https://a/1.jpg,https://a/2.jpg,https://a/3.jpg");
});

Deno.test("still splits multi-value fields if the vendor sends commas", () => {
  const v = mapRow(
    row({ "Photo URLs": "https://a/1.jpg, https://a/2.jpg" }),
    SOURCE,
  );
  assertEquals(v.images, "https://a/1.jpg,https://a/2.jpg");
});

Deno.test("header matching ignores case, spaces and punctuation", () => {
  const v = mapRow(
    normalizeRow({ "stock_number": "ABC1", make: "Kia", MODEL: "Rio" }),
    SOURCE,
  );
  assertEquals(v.stock, "ABC1");
  assertEquals(v.make, "Kia");
  assertEquals(v.model, "Rio");
});

// ─── The real vAuto export ──────────────────────────────────────────────────
//
// Everything above uses the column names vAuto's spec sheet implied. These use
// the ones they actually send, taken verbatim from the exports in
// docs/sample_feeds/. The two sets differ enough that the earlier tests all
// passed while every vehicle arrived with no photos and no colour.

/// A row spelled the way vAuto spells it.
function vautoRow(overrides: Record<string, string> = {}) {
  return normalizeRow({
    DealerId: "goodevw",
    "Dealer Name": "Goode Motor Volkswagen Mazda",
    VIN: "3VVGR7RM0TM137302",
    "Stock #": "TN137302",
    "New/Used": "N",
    Year: "2026",
    Make: "Volkswagen",
    Model: "Tiguan",
    Body: "4D Sport Utility",
    Transmission: "8-Speed Automatic",
    Series: "2.0T SE R-Line Black",
    "Body Door Ct": "4",
    Odometer: "1",
    "Engine Cylinder Ct": "4",
    "Engine Displacement": "2",
    "Drivetrain Desc": "AWD",
    Colour: "Monterey Blue Pearl",
    "Interior Color": "Titan Black",
    MSRP: "41936",
    Price: "38081",
    Certified: "",
    Engine: "2.0L TSI DOHC",
    Fuel: "Gasoline",
    "Photo Url List": "https://a/1.jpeg|https://a/2.jpeg",
    "Dealer City": "Twin Falls",
    "Dealer Region": "ID",
    ...overrides,
  });
}

Deno.test("maps a row spelled the way vAuto actually spells it", () => {
  const v = mapRow(vautoRow(), SOURCE);

  assertEquals(v.external_id, "vauto:48213:TN137302"); // "Stock #"
  assertEquals(v.trim, "2.0T SE R-Line Black"); // "Series"
  assertEquals(v.mileage, 1); // "Odometer"
  assertEquals(v.doors, "4"); // "Body Door Ct"
  assertEquals(v.color, "Blue"); // "Colour"
  assertEquals(v.location, "Twin Falls, ID"); // no location column at all
  assertEquals(v.images, "https://a/1.jpeg,https://a/2.jpeg"); // "Photo Url List"
  assertEquals(v.engine_options, "2.0L · 4 cyl · AWD"); // "... Ct", "... Desc"
  assertEquals(v.price, 41936);
  assertEquals(v.promotion, 38081);
});

Deno.test("strips the door count vAuto prefixes onto every body style", () => {
  const body = (raw: string) => mapRow(vautoRow({ Body: raw }), SOURCE).body;

  assertEquals(body("4D Sport Utility"), "SUV");
  assertEquals(body("4D Sedan"), "Sedan");
  assertEquals(body("2D Coupe"), "Coupe");
  assertEquals(body("4D Hatchback"), "Hatchback");
  assertEquals(body("3D Cargo Van"), "Van");
  assertEquals(body("2D Convertible"), "Convertible");
});

Deno.test("every cab style is a pickup truck", () => {
  const body = (raw: string) => mapRow(vautoRow({ Body: raw }), SOURCE).body;

  assertEquals(body("4D Crew Cab"), "Pickup Truck");
  assertEquals(body("4D SuperCrew"), "Pickup Truck");
  assertEquals(body("4D Quad Cab"), "Pickup Truck");
  assertEquals(body("4D Mega Cab"), "Pickup Truck");
  assertEquals(body("4D CrewMax"), "Pickup Truck");
  assertEquals(body("Super Cab"), "Pickup Truck");
  assertEquals(body("2D Standard Cab"), "Pickup Truck");
});

Deno.test("reads the gearbox out of vAuto marketing copy", () => {
  const t = (raw: string) => mapRow(vautoRow({ Transmission: raw }), SOURCE);

  assertEquals(t("8-Speed Automatic with Tiptronic").transmission, "Automatic");
  assertEquals(t("Allison 1000 6-Speed Automatic").transmission, "Automatic");
  assertEquals(t("6-Speed Manual").transmission, "Manual");
  assertEquals(t("CVT with Xtronic").transmission, "CVT");
  assertEquals(t("Lineartronic CVT").transmission, "CVT");
  assertEquals(t("Continuously Variable (ECVT)").transmission, "CVT");
  // A DSG is described as an automatic, but it is a dual-clutch first.
  assertEquals(
    t("7-Speed DSG Automatic with Tiptronic").transmission,
    "Semi-Auto / DCT",
  );
  // Toyota names the torque converter instead of saying "automatic".
  assertEquals(t("5-Speed with ECT").transmission, "Automatic");
});

Deno.test("keeps the speed count vAuto has no column for", () => {
  assertEquals(
    mapRow(vautoRow({ Transmission: "10-Speed Automatic" }), SOURCE).speed,
    "10",
  );
  assertEquals(mapRow(vautoRow({ Transmission: "CVT" }), SOURCE).speed, null);
});

Deno.test("does not repeat the gearbox when it adds nothing", () => {
  assertEquals(
    mapRow(vautoRow({ Transmission: "8-Speed Automatic" }), SOURCE)
      .transmission_options,
    "8-Speed Automatic",
  );
  assertEquals(
    mapRow(vautoRow({ Transmission: "Automatic" }), SOURCE)
      .transmission_options,
    null,
  );
});

Deno.test("reduces a paint name to a colour the chips can match", () => {
  const c = (raw: string) => mapRow(vautoRow({ Colour: raw }), SOURCE).color;

  assertEquals(c("Monterey Blue Pearl"), "Blue");
  assertEquals(c("Summit White"), "White");
  assertEquals(c("Magnetic Gray Metallic"), "Gray");
  assertEquals(c("Billet Silver Metallic Clearcoat"), "Silver");
  assertEquals(c("Diamond Black Crystal Pearlcoat"), "Black");
  assertEquals(c("Delmonico Red Pearlcoat"), "Red");
  assertEquals(c("Hypergreen Clearcoat"), "Green");
  assertEquals(c("Midnight Blue Metallic"), "Navy");
  // "Ivory White" is white, not beige — specificity beats reading order.
  assertEquals(c("Ivory White Tri-Coat Pearlcoat"), "White");
  // Two-tone: the roof follows "w/" or a slash and is not what is filtered on.
  assertEquals(c("Monterey Blue w/Deep Black Roof"), "Blue");
  assertEquals(c("Bright Moss Green/Blk Rf"), "Green");
  // A name with no colour word in it is kept rather than guessed at.
  assertEquals(c("Area 51"), "Area 51");
});

Deno.test("recognises all-wheel drive under its trade names", () => {
  const d = (raw: string) =>
    mapRow(vautoRow({ "Drivetrain Desc": raw }), SOURCE).engine_options;

  assertEquals(d("quattro"), "2.0L · 4 cyl · AWD");
  assertEquals(d("4MATIC®"), "2.0L · 4 cyl · AWD");
  assertEquals(d("FWD"), "2.0L · 4 cyl · FWD");
  // The chip reads "4WD / 4x4"; the filter compares text, so the label has to
  // be the chip verbatim or a 4WD truck never comes back from that filter.
  assertEquals(d("4WD"), "2.0L · 4 cyl · 4WD / 4x4");
});

Deno.test("reads the single letter vAuto uses for New and Used", () => {
  assertEquals(mapRow(vautoRow({ "New/Used": "N" }), SOURCE).status, "New");
  assertEquals(
    mapRow(vautoRow({ "New/Used": "U" }), SOURCE).status,
    "Pre-Owned",
  );
  assertEquals(
    mapRow(vautoRow({ "New/Used": "U", Certified: "Yes" }), SOURCE).status,
    "Certified Pre-Owned",
  );
});

Deno.test("a used car with no MSRP is not discounted to its asking price", () => {
  // Most of the used inventory ships MSRP empty and Price filled.
  const v = mapRow(vautoRow({ MSRP: "", Price: "39999" }), SOURCE);
  assertEquals(v.price, 39999);
  assertEquals(v.promotion, null);
});

Deno.test("the dealer id is read through the same aliases as the columns", () => {
  assertEquals(pickDealerRef(vautoRow()), "goodevw");
  assertEquals(pickDealerRef(normalizeRow({ "Dealer Code": "48213" })), "48213");
  assertEquals(pickDealerRef(normalizeRow({ Make: "Kia" })), "");
});
