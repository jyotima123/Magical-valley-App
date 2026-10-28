// ---------------------------------------------------------------------------
// CSV row -> vehicle_listings row.
//
// The vocabulary tables below are a deliberate port of LiftKitVehicleMapper in
// lib/modules/cars/liftkit_api_service.dart. They exist twice because LiftKit is
// normalized on read (in Dart, client-side) while a delivered file is normalized
// on ingest (here, server-side). Both answer to the same authority: the enum
// lists in docs/cars_api_provider_integration_guide.md. Filters compare against
// CarData's option lists, so a value that misses these tables does not merely
// look untidy — it drops the vehicle out of every filtered result set.
//
// Keep this file and the Dart mapper in step. mapper_test.ts mirrors
// test/liftkit_vehicle_mapper_test.dart case for case.
// ---------------------------------------------------------------------------

/// Header matching is forgiving: "Stock #", "stock_number" and "StockNumber"
/// all reduce to a name the alias lists below carry.
export function normalizeHeader(raw: string): string {
  return raw.toLowerCase().replace(/[^a-z0-9]/g, "");
}

/// Candidate column names per field, best match first.
///
/// The names marked below are confirmed against the real vAuto exports in
/// docs/sample_feeds/. Their column set is not the one the spec sheet suggests:
/// door and cylinder counts end in "Ct", the photo field is a "List", the
/// exterior colour column is spelled the British way, and there is no location
/// or sold column at all. The unmarked names are hedges kept for other vendors
/// and for vAuto templates we have not been sent.
const FIELD_ALIASES: Record<string, string[]> = {
  dealerRef: ["dealerid", "dealercode", "storeid", "rooftopid", "dealernumber"],
  dealerName: ["dealername", "storename", "rooftop"],
  // vAuto: "Stock #" -> stock
  stock: ["stocknumber", "stock", "stockno", "stockid", "dealerstocknumber"],
  vin: ["vin", "vinnumber"],
  year: ["year", "modelyear", "vehicleyear"],
  make: ["make", "vehiclemake", "manufacturer"],
  model: ["model", "vehiclemodel"],
  // vAuto: "Series" holds the trim ("2.0T SE R-Line Black", "Big Horn").
  trim: ["trim", "trimlevel", "series", "seriesdetail", "style"],
  body: ["bodystyle", "body", "bodytype", "vehiclebodystyle"],
  type: ["type", "vehicletype", "segment"],
  // "type" is last: some vendors put New/Used in it, others put SUV/Truck. The
  // more specific names win, and mapStatus falls back to Pre-Owned for anything
  // it does not recognise, so a body style landing here is harmless.
  // vAuto: "New/Used" -> newused, sent as a single letter N or U.
  condition: ["condition", "newused", "vehiclecondition", "status", "type"],
  certified: ["certified", "cpo", "iscertified", "certifiedpreowned"],
  sold: ["sold", "issold", "removed", "inventorystatus"],
  // vAuto: "Odometer"
  mileage: ["mileage", "odometer", "miles"],
  listPrice: ["msrp", "listprice", "retailprice", "askingprice"],
  salePrice: [
    "internetprice",
    "sellingprice",
    "specialprice",
    "saleprice",
    "price",
  ],
  // A generic colour ("Blue") is what the colour chips compare against; the
  // paint name ("Monterey Blue Pearl") is all vAuto sends, so mapColor reduces
  // it. Mirrors LiftKit preferring color.simple over color.name.
  color: [
    "exteriorcolorgeneric",
    "exteriorcolour",
    "exteriorcolor",
    "colour",
    "color",
    "extcolor",
  ],
  interior: ["interiorcolour", "interiorcolor", "interior", "intcolor"],
  transmission: ["transmission", "transmissiontype"],
  transmissionDesc: ["transmissiondescription", "transmissionspeed", "speed"],
  engine: ["engine", "enginedescription"],
  // vAuto: "Engine Displacement", a bare number of litres.
  displacement: [
    "enginedisplacement",
    "displacement",
    "enginesize",
    "displacementliters",
  ],
  // vAuto: "Engine Cylinder Ct"
  cylinders: [
    "enginecylinderct",
    "enginecylinders",
    "enginecylindercount",
    "cylinders",
    "cylinderct",
    "cyl",
  ],
  fuel: ["fueltype", "fuel"],
  // vAuto: "Drivetrain Desc"
  drivetrain: [
    "drivetraindesc",
    "drivetraindescription",
    "drivetrain",
    "drivetype",
    "driveline",
    "drivewheels",
    "drive",
  ],
  // vAuto: "Body Door Ct"
  doors: [
    "bodydoorct",
    "doorcount",
    "bodydoorcount",
    "doors",
    "doorct",
    "numberofdoors",
  ],
  description: ["description", "comments", "sellernotes", "vehiclecomments"],
  features: ["features", "options", "optionlist", "equipment"],
  packages: ["packages", "packagelist"],
  // vAuto: "Photo Url List", pipe-delimited, 0-41 per vehicle.
  photos: [
    "photourllist",
    "photourls",
    "photourl",
    "photos",
    "imageurllist",
    "imageurls",
    "images",
    "pictureurls",
  ],
  videos: ["videourllist", "videourls", "videourl", "videos"],
  location: ["location", "lot", "dealerlocation"],
  // vAuto sends the rooftop address in parts; mapRow joins city and region.
  city: ["dealercity", "city", "locationcity"],
  region: ["dealerregion", "dealerstate", "state", "province", "locationstate"],
};

export interface MappedVehicle {
  source: string;
  external_id: string;
  stock: string;
  vin: string | null;
  year: number;
  make: string;
  model: string;
  trim: string | null;
  body: string | null;
  status: string;
  mileage: number;
  color: string | null;
  interior: string | null;
  transmission: string | null;
  speed: string | null;
  engine_type: string | null;
  fuel: string | null;
  doors: string | null;
  price: number;
  promotion: number | null;
  description: string | null;
  location: string | null;
  images: string | null;
  videos: string | null;
  engine_options: string | null;
  package_options: string | null;
  transmission_options: string | null;
  addons_description: string | null;
  is_sold: boolean;
}

export type CsvRow = Record<string, string>;

/// Reads a logical field out of a row whose keys are already normalized.
function pick(row: CsvRow, field: string): string | null {
  for (const alias of FIELD_ALIASES[field] ?? []) {
    const value = row[alias];
    if (value !== undefined && value.trim() !== "") return value.trim();
  }
  return null;
}

/// The dealer id as the file spells it. Exported because index.ts groups rows
/// by dealership before mapping them, and has to read the column the same way
/// the mapper does rather than keep its own shorter list of spellings.
export function pickDealerRef(row: CsvRow): string {
  return pick(row, "dealerRef") ?? "";
}

// ─── Vocabulary normalization (ported from LiftKitVehicleMapper) ────────────

/// Feeds say New/Used; our status chips say Pre-Owned, with certified cars
/// promoted to their own chip. Anything unrecognised is Pre-Owned, never New —
/// mislabelling a used car as new is the more damaging direction. vAuto
/// abbreviates to a single letter.
export function mapStatus(raw: string | null, certified: boolean): string {
  if (certified) return "Certified Pre-Owned";
  switch (raw?.toLowerCase().trim()) {
    case "new":
    case "n":
      return "New";
    case "cpo":
    case "certified":
    case "certified pre-owned":
      return "Certified Pre-Owned";
    default:
      return "Pre-Owned";
  }
}

/// vAuto prefixes the body with a door count — "4D Sport Utility", "2D Coupe" —
/// and names pickups by their cab: "4D Crew Cab", "4D SuperCrew", "Super Cab",
/// "4D Mega Cab". Neither reaches a body chip unaided, and between them they
/// cover every vehicle in both sample exports.
export function mapBody(body: string | null, type: string | null): string | null {
  switch (type?.toLowerCase().trim()) {
    case "suv":
      return "SUV";
    case "truck":
      return "Pickup Truck";
  }

  // "4D Sport Utility" -> "sport utility". The door count has its own column.
  const cleaned = (body ?? "")
    .toLowerCase()
    .trim()
    .replace(/^\d+\s*d(?:r|oor)?\s+/, "");
  if (cleaned === "") return body ?? type;

  // Every cab style is a pickup. Matching the word "cab" covers Crew, Quad,
  // Mega, Double, Access, King, Club, Standard and Super without listing each,
  // and SuperCrew/CrewMax are the closed-up spellings Ford and Toyota use.
  if (/\bcab\b/.test(cleaned) || /supercrew|crewmax|supercab|megacab/.test(cleaned)) {
    return "Pickup Truck";
  }

  switch (cleaned) {
    case "pickup":
    case "pickup truck":
    case "truck":
      return "Pickup Truck";
    case "passenger van":
    case "cargo van":
    case "van":
    case "full size van":
      return "Van";
    case "minivan":
    case "mini-van":
      return "Minivan";
    case "sedan":
      return "Sedan";
    case "coupe":
      return "Coupe";
    case "convertible":
    case "roadster":
      return "Convertible";
    case "hatchback":
    case "liftback":
      return "Hatchback";
    case "wagon":
    case "sport wagon":
    case "station wagon":
      return "Wagon";
    case "crossover":
      return "Crossover";
    case "sport utility":
    case "sport utility vehicle":
    case "sportutility":
    case "suv":
      return "SUV";
  }
  return body ?? type;
}

export function mapFuel(raw: string | null): string | null {
  switch (raw?.toLowerCase().trim()) {
    case "gas":
    case "gasoline":
    case "unleaded":
    case "petrol":
      return "Gasoline";
    case "diesel":
      return "Diesel";
    case "hybrid":
    case "gas/electric hybrid":
      return "Hybrid";
    case "plug-in hybrid":
    case "plugin hybrid":
    case "phev":
      return "Plug-in Hybrid";
    case "electric":
    case "ev":
      return "Electric";
    case "flex":
    case "flex fuel":
    case "ethanol":
    case "e85":
      return "Flex Fuel";
    case "hydrogen":
      return "Hydrogen";
    default:
      return raw;
  }
}

/// vAuto sends the gearbox as marketing copy — "8-Speed Automatic with
/// Tiptronic", "Allison 1000 6-Speed Automatic", "CVT with Xtronic" — so this
/// matches substrings rather than whole values. Order matters: a DSG is
/// described as an automatic too, and the more specific kind has to win.
export function mapTransmission(raw: string | null): string | null {
  const value = raw?.toLowerCase().trim();
  if (!value) return raw;

  if (
    /\bcvt\b|continuously variable|lineartronic|xtronic|\becvt\b|\bivt\b/
      .test(value)
  ) {
    return "CVT";
  }
  if (/dual clutch|\bdsg\b|\bdct\b|\bpdk\b|semi-?auto/.test(value)) {
    return "Semi-Auto / DCT";
  }
  if (/\bmanual\b/.test(value)) return "Manual";
  if (/\bautomatic\b|\bauto\b/.test(value)) return "Automatic";
  // Trade names for a torque-converter automatic that omit the word itself:
  // Toyota "5-Speed with ECT", VW Tiptronic, Hyundai Shiftronic.
  if (
    /\bect\b|tiptronic|shiftronic|sportmatic|select-?shift|steptronic|torqshift|geartronic/
      .test(value)
  ) {
    return "Automatic";
  }
  return raw;
}

/// "8-Speed Automatic" -> "8", for the detail screen Speeds row. vAuto has no
/// separate speed column, so without this the number is lost.
export function parseSpeed(raw: string | null): string | null {
  const match = raw?.match(/(\d+)[\s-]*speed/i);
  return match ? match[1] : null;
}

/// Drivetrain arrives as a marque trade name as often as an acronym — quattro,
/// 4MATIC, xDrive and 4MOTION all mean all-wheel drive.
export function mapDrivetrain(raw: string | null): string | null {
  const value = raw?.toLowerCase().trim();
  if (!value) return raw;

  if (/\b4wd\b|\b4x4\b|four wheel|4-wheel|fourwheel/.test(value)) {
    return "4WD / 4x4";
  }
  if (
    /\bawd\b|all wheel|all-wheel|quattro|4matic|xdrive|4motion|sh-awd|allgrip/
      .test(value)
  ) {
    return "AWD";
  }
  if (/\bfwd\b|front wheel|front-wheel/.test(value)) return "FWD";
  if (/\brwd\b|rear wheel|rear-wheel|\b2wd\b|\b4x2\b/.test(value)) return "RWD";
  return raw;
}

/// The colour chips are fifteen generic names; vAuto sends the paint name
/// ("Monterey Blue Pearl", "Summit White", "Magnetic Gray Metallic"). Scanning
/// for a generic token inside it is what makes the colour filter select
/// anything at all. A name with no generic token in it is kept verbatim rather
/// than dropped — it still shows on the detail screen, it just cannot match a
/// chip, which is the honest outcome for "Area 51" or "Frostbite".
const COLOR_TOKENS: [RegExp, string][] = [
  // Specific before general: navy is also blue, burgundy is also red, and
  // "Ivory White" is white rather than beige.
  [/\bnavy\b|midnight blue|\bindigo\b/, "Navy"],
  [/\bmaroon\b|burgundy|\bruby\b|\bwine\b|\bgarnet\b/, "Maroon"],
  [/\bsilver\b|quicksilver|silverstone/, "Silver"],
  [/\bwhite\b|\balabaster\b|\bblizzard\b|\bfrost\b/, "White"],
  [/\bblack\b|\bonyx\b|\bebony\b|\bcaviar\b|\bnocturne\b|\bobsidian\b/, "Black"],
  [
    /\bgra[ey]\b|graphite|charcoal|gunmetal|\bslate\b|\bsteel\b|granite|\bash\b|iridium|\bmagnetic\b|\bindium\b|mineral|moonstone|\bstone\b|\bquartz\b|\bcement\b/,
    "Gray",
  ],
  // Some OEM names glue the colour word to a prefix — Redline, Hypergreen —
  // so those two tokens are matched without a leading word boundary.
  [/\bred|torred|crimson|\bscarlet\b|\bcherry\b|inferno|\btamale\b/, "Red"],
  [/\bblue\b|blueprint|\bcobalt\b|\bazure\b/, "Blue"],
  [/green|\bmoss\b|\bolive\b|\bemerald\b|\bavocado\b/, "Green"],
  [
    /\bbrown\b|\bbronze\b|\bcopper\b|\bmocha\b|\bsable\b|chocolate|espresso|\bmahogany\b/,
    "Brown",
  ],
  [/\bbeige\b|\btan\b|\bsand\b|sandstone|\bivory\b|\bcream\b|\bkhaki\b/, "Beige"],
  [/\bgold\b|golden|champagne/, "Gold"],
  // Late, because "White Platinum" is a white car and has to match white first.
  [/\bplatinum\b/, "Silver"],
  [/\borange\b/, "Orange"],
  [/\byellow\b|\bamber\b/, "Yellow"],
  [/\bpurple\b|\bviolet\b|\bplum\b|snazzberry/, "Purple"],
];

export function mapColor(raw: string | null): string | null {
  if (raw === null) return null;
  // Two-tone names put the roof after a slash or "w/", and the body colour is
  // the one a buyer filters on: "Monterey Blue w/Deep Black Roof" -> Blue.
  const primary = raw.toLowerCase().split(/\s+w\/|\//)[0].trim();
  for (const [pattern, generic] of COLOR_TOKENS) {
    if (pattern.test(primary)) return generic;
  }
  return raw;
}

// ─── Primitive coercion ─────────────────────────────────────────────────────

/// Dealer feeds send prices as "$25,000.00" as often as they send numbers.
export function toNumber(raw: string | null): number | null {
  if (raw === null) return null;
  const cleaned = raw.replace(/[^0-9.\-]/g, "");
  if (cleaned === "") return null;
  const parsed = Number(cleaned);
  return Number.isFinite(parsed) ? parsed : null;
}

export function toInt(raw: string | null): number | null {
  const n = toNumber(raw);
  return n === null ? null : Math.round(n);
}

export function toBool(raw: string | null): boolean {
  if (raw === null) return false;
  return ["1", "true", "yes", "y", "t", "sold", "certified"].includes(
    raw.toLowerCase().trim(),
  );
}

/// Multi-value fields arrive pipe-delimited — confirmed in both vAuto exports
/// for photos, features and packages — but a vendor that sends commas should
/// not cost us every photo but the first.
export function splitMulti(raw: string | null): string[] {
  if (raw === null) return [];
  const delimiter = raw.includes("|") ? "|" : ",";
  return raw
    .split(delimiter)
    .map((s) => s.trim())
    .filter((s) => s !== "");
}

/// Descriptions may contain HTML; the detail screen renders plain text.
export function toText(raw: string | null): string | null {
  if (raw === null) return null;
  const stripped = raw
    .replace(/<br\s*\/?>|<\/p>|<\/div>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&amp;/g, "&")
    .replace(/&#039;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&nbsp;/g, " ")
    // A paragraph that ends and is followed by a break produces two newlines
    // out of what renders as one; collapse any run back to a single break.
    .replace(/\s*\n\s*/g, "\n")
    .trim();
  return stripped === "" ? null : stripped;
}

/// "2" -> "2.0L", "2.5" -> "2.5L". vAuto sends displacement as a bare number.
export function displacementLabel(raw: string | null): string | null {
  const litres = toNumber(raw);
  if (litres === null || litres <= 0) return null;
  return `${litres.toFixed(1)}L`;
}

// ─── Row mapping ────────────────────────────────────────────────────────────

export class SkippedRow extends Error {}

/// Returns the row to upsert, or throws SkippedRow when the record has nothing
/// the UI could render. Mirrors LiftKitVehicleMapper.toListing returning null.
export function mapRow(row: CsvRow, source: string): MappedVehicle {
  const stock = pick(row, "stock");
  const vin = pick(row, "vin");
  const make = pick(row, "make");
  const model = pick(row, "model");

  // Without an identifier the vehicle cannot be de-duplicated across runs or
  // reconciled against the next file; without make/model the card is blank.
  const identifier = stock ?? vin;
  if (identifier === null) throw new SkippedRow("no stock number or VIN");
  if (make === null || model === null) throw new SkippedRow("no make/model");

  // The advertised price is what the dealer is actually asking; when a higher
  // list price also exists, it is shown struck through.
  const listPrice = toNumber(pick(row, "listPrice"));
  const salePrice = toNumber(pick(row, "salePrice")) ?? listPrice;
  const hasDiscount =
    listPrice !== null && salePrice !== null && salePrice < listPrice;

  const rawTransmission = pick(row, "transmission");
  const transmission = mapTransmission(rawTransmission);
  const transmissionDesc = pick(row, "transmissionDesc");

  // vehicle_listings has no drivetrain column, but VehicleSearchFilters matches
  // the drive-type chips against the listing descriptive text (_haystack), so
  // the canonical label has to live in a text column to be filterable at all.
  // Engine Options is where a dealer site prints it anyway, and the label has
  // to be the chip verbatim — "4WD / 4x4", not "4WD" — for the match to land.
  const drivetrain = mapDrivetrain(pick(row, "drivetrain"));
  const displacement = displacementLabel(pick(row, "displacement"));
  const cylinders = pick(row, "cylinders");
  const engineOptions = [
    displacement,
    cylinders ? `${cylinders} cyl` : null,
    drivetrain,
  ].filter((part): part is string => part !== null);

  // Features and options are a multi-value field; the DB column is free text.
  const features = splitMulti(pick(row, "features"));

  // vAuto has no location column — it sends the rooftop address in parts.
  const city = pick(row, "city");
  const region = pick(row, "region");
  const location = pick(row, "location") ??
    ([city, region].filter((part): part is string => part !== null).join(", ") ||
      null);

  return {
    source,
    external_id: `${source}:${identifier}`,
    stock: stock ?? vin!,
    vin,
    year: toInt(pick(row, "year")) ?? 0,
    make,
    model,
    trim: pick(row, "trim"),
    body: mapBody(pick(row, "body"), pick(row, "type")),
    status: mapStatus(pick(row, "condition"), toBool(pick(row, "certified"))),
    mileage: toInt(pick(row, "mileage")) ?? 0,
    color: mapColor(pick(row, "color")),
    interior: pick(row, "interior"),
    transmission,
    speed: transmissionDesc ?? parseSpeed(rawTransmission),
    engine_type: pick(row, "engine") ?? displacement,
    fuel: mapFuel(pick(row, "fuel")),
    doors: pick(row, "doors"),
    // price is NOT NULL in the schema. A missing price means "Call for price"
    // (VehicleListing.hasPrice), not a free car — dealer feeds routinely omit
    // it on fresh trade-ins.
    price: (hasDiscount ? listPrice : salePrice) ?? 0,
    promotion: hasDiscount ? salePrice : null,
    description: toText(pick(row, "description")),
    location,
    // images/videos are comma-joined text columns, not arrays — see
    // VehicleListing._splitComma on the read side.
    images: splitMulti(pick(row, "photos")).join(",") || null,
    videos: splitMulti(pick(row, "videos")).join(",") || null,
    engine_options: engineOptions.join(" · ") || null,
    package_options: splitMulti(pick(row, "packages")).join(", ") || null,
    // Only worth keeping when it says more than the normalized value does:
    // "8-Speed Automatic with Tiptronic" is informative, a second "Automatic"
    // is a duplicated row on the detail screen.
    transmission_options: transmissionDesc ??
      (rawTransmission !== transmission ? rawTransmission : null),
    addons_description: features.join(", ") || null,
    is_sold: toBool(pick(row, "sold")),
  };
}

/// Normalizes every header once, so `pick` can look up by canonical name.
export function normalizeRow(row: Record<string, string>): CsvRow {
  const out: CsvRow = {};
  for (const [key, value] of Object.entries(row)) {
    out[normalizeHeader(key)] = value ?? "";
  }
  return out;
}
