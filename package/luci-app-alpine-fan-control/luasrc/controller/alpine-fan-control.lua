module("luci.controller.alpine-fan-control", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/alpine-fan-control") then
		return
	end

	local page = entry({"admin", "system", "alpine-fan-control"}, cbi("alpine-fan-control"))
	page.title = _("Fan Control")
	page.order = 58
	page.dependent = true
	page.acl_depends = { "luci-app-alpine-fan-control" }
end
