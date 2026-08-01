package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local aws_profiles = require("config.aws_profiles")

local fixture = [[
[profile labs]
sso_session = sso-main
sso_account_id = 154805902702
sso_role_name = AWSAdministratorAccess
region = us-east-1
[sso-session sso-main]
sso_start_url = https://petlab.awsapps.com/start
sso_region = us-east-1
sso_registration_scopes = sso:account:access
[profile management]
sso_session = sso-main
sso_account_id = 503036359418
sso_role_name = AWSAdministratorAccess
region = us-east-1
[profile prod]
sso_session = sso-main
sso_account_id = 325875666703
sso_role_name = AWSAdministratorAccess
[profile plain-no-sso]
region = eu-west-2
]]

local fixture_path = vim.fn.tempname()
local fh = io.open(fixture_path, "w")
fh:write(fixture)
fh:close()

local profiles = aws_profiles.profiles(fixture_path)

eq(#profiles, 3, "sso-session blocks and non-SSO profiles are excluded")
eq(profiles[1], {
	profile = "labs",
	account_id = "154805902702",
	role = "AWSAdministratorAccess",
	region = "us-east-1",
}, "profile before the sso-session block is parsed with its region")
eq(profiles[2], {
	profile = "management",
	account_id = "503036359418",
	role = "AWSAdministratorAccess",
	region = "us-east-1",
}, "profile after the sso-session block is parsed")
eq(profiles[3], {
	profile = "prod",
	account_id = "325875666703",
	role = "AWSAdministratorAccess",
	region = nil,
}, "a profile missing region is parsed with a nil region")

os.remove(fixture_path)

eq(aws_profiles.profiles("/nonexistent/path/for/testing"), {}, "a missing config file resolves to an empty list")

-- profile names may contain spaces; the row/decode codec must round-trip regardless
local spaced_row = aws_profiles.row({ profile = "my profile", account_id = "111122223333", role = "ReadOnly" })
eq(
	aws_profiles.decode_row(spaced_row),
	{ profile = "my profile", account_id = "111122223333", role = "ReadOnly" },
	"row/decode round-trips a profile name containing spaces"
)

local no_role_row = aws_profiles.row({ profile = "labs", account_id = "154805902702", role = nil })
eq(
	aws_profiles.decode_row(no_role_row),
	{ profile = "labs", account_id = "154805902702", role = "" },
	"row/decode round-trips a missing role as an empty string"
)

-- AWS_CONFIG_FILE override
local override_path = vim.fn.tempname()
local override_fh = io.open(override_path, "w")
override_fh:write("[profile override]\nsso_account_id = 999900001111\nsso_role_name = ReadOnly\n")
override_fh:close()
vim.env.AWS_CONFIG_FILE = override_path
eq(aws_profiles.profiles(), {
	{ profile = "override", account_id = "999900001111", role = "ReadOnly", region = nil },
}, "AWS_CONFIG_FILE env override is honored when no explicit path is given")
vim.env.AWS_CONFIG_FILE = nil
os.remove(override_path)

local notified = {}
local original_notify = vim.notify
vim.notify = function(msg, level)
	table.insert(notified, { msg = msg, level = level })
end

local original_reg = vim.fn.getreg("+")
local row = aws_profiles.row({ profile = "prod", account_id = "325875666703", role = "AWSAdministratorAccess" })

local id_decoded = aws_profiles.yank_account_id(row)
eq(id_decoded.account_id, "325875666703", "yank_account_id returns the decoded account id")
eq(vim.fn.getreg("+"), "325875666703", "the default action yanks the account id to the + register")
eq(notified[#notified].msg, "Yanked account ID: 325875666703 (prod)", "the default action notifies with the account id and profile")

local name_decoded = aws_profiles.yank_profile_name(row)
eq(name_decoded.profile, "prod", "yank_profile_name returns the decoded profile")
eq(vim.fn.getreg("+"), "prod", "the alt action yanks the profile name to the + register")
eq(notified[#notified].msg, "Yanked profile name: prod", "the alt action notifies with the profile name")

vim.fn.setreg("+", original_reg)
vim.notify = original_notify

print("PASS aws_profiles parses SSO config, excludes non-account profiles, and round-trips display rows")
