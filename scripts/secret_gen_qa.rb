require "jwt"

key_file = "/Users/alisson/Downloads/AuthKey_58KL9J525R.p8"
team_id = "W9JT65YQ5L"
client_id = "om.magicvalleycentral.mvcapp.qa.service"
key_id = "58KL9J525R"
validity_period = 180 # In days. Max 180 (6 months) according to Apple docs.

private_key = OpenSSL::PKey::EC.new IO.read key_file

token = JWT.encode(
	{
		iss: team_id,
		iat: Time.now.to_i,
		exp: Time.now.to_i + 86400 * validity_period,
		aud: "https://appleid.apple.com",
		sub: client_id
	},
	private_key,
	"ES256",
	header_fields=
	{
		kid: key_id 
	}
)
puts token