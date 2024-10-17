local c = require "conf"
local tpls = require "//templates/tpls.htt"

-- TODO: temporary hack to quiet LSP
local htt = htt
local render = render

-- Proposed structure
---------------------
--     <out>/
--         ssh
--         scp
--         mutagen
--         qcmdr
--             (can list vm dirs, calls out to vm-dir scripts for impl)
--         vm.<vm>/
--             pid
--             monitor
--             serial
--             ctrl
--                 (support start/stop/status)
--         data/
--             ssh/
--                 ssh-conf
--                 <ctrl files...>
--             mutagen/
--                 <whatever mess mutagen makes>

local function table_copy (t)
	-- create a shallow copy of table `t`
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = v
	end
	return copy
end


local function render_executable(tpl, fpath, conf)
	render(tpl, fpath, conf)
	os.execute(string.format([[chmod +x "%s"]], fpath))
end


local cwd = htt.fs.cwd()
local cwdAbsPath = cwd:path()

local out = htt.fs.path_join(cwdAbsPath, "out")


-- SSH
-----------------------------------
local dir_data_ssh = htt.fs.path_join(out, "data", "ssh")
cwd:makePath(dir_data_ssh)

local ssh_all_conf = table_copy(c.ssh_conf_base)
ssh_all_conf.ControlPath = htt.fs.path_join(dir_data_ssh, "ctrl-%r@%h-%p")

local ssh_conf_fpath = htt.fs.path_join(dir_data_ssh, "ssh-conf")
local ssh_hosts = c.map(c.vms, function(vm)
	return {
		name = vm.name,
		ssh = vm.ssh or {},
	}
end)
render(tpls.Config, ssh_conf_fpath, {
	all = ssh_all_conf,
	hosts = ssh_hosts,
})

local ssh_bin_fpath = htt.fs.path_join(out, "ssh")
render_executable(tpls.BinWrap, ssh_bin_fpath, {
	bin = "ssh",
	conf_fpath = ssh_conf_fpath,
})

render_executable(tpls.BinWrap, htt.fs.path_join(out, "scp"), {
	bin = "scp",
	conf_fpath = ssh_conf_fpath,
})


-- qcmdr -- the wrapper/management script
-----------------------------------
local ssh_conf_rel_fpath = htt.fs.path_join(
	"data", "ssh", "ssh-conf"
)

render_executable(tpls.QcmdrScript, htt.fs.path_join(out, "qcmdr"), {
	ssh_conf_fpath = ssh_conf_rel_fpath,
})

-- Mutagen
-----------------------------------
-- TODO: relpath refactor, gotta move the "out" part to a separate var
local mutagen_data_dir_relpath = htt.fs.path_join("data", "mutagen")
cwd:makePath(mutagen_data_dir_relpath)

render_executable(tpls.MutagenBinWrap, htt.fs.path_join(out, "mutagen"), {
	ssh_bin_fpath = "ssh",
	data_dir_fpath = mutagen_data_dir_relpath,
})


-- VM configs
-----------------------------------
for _, vm in ipairs(c.vms) do
	-- We use paths relative to qcmdr script root in the scripts.
	--
	-- We do this because the qcmdr script will set CWD to its own
	-- basedir and that using relpaths will ensure that you can move
	-- the generated scripts around without anything breaking.
	-- (-> unlike a Python virtual environment, for example)
	local vm_relpath = htt.fs.path_join("vm." .. vm.name)
	local vm_path = htt.fs.path_join(out, vm_relpath)
	cwd:makePath(vm_path)
	local pid_fpath = htt.fs.path_join(vm_relpath, "pid")
	local monitor_fpath = htt.fs.path_join(vm_relpath, "monitor")
	local serial_fpath = htt.fs.path_join(vm_relpath, "serial")

	-- TODO add monitor, serial and daemonize args
	local vm_args = table_copy(vm.args)
	local extra_vm_args = {
		"-pidfile", "${SCRIPT_DIR}/" .. pid_fpath,
		"-monitor", string.format("unix:${SCRIPT_DIR}/%s,server,nowait", monitor_fpath),
		"-serial", "file:${SCRIPT_DIR}/" .. serial_fpath,
		"-daemonize"
	}
	-- append extra args
	table.move(extra_vm_args, 1, #extra_vm_args, #vm_args + 1, vm_args)

	local script_fpath = htt.fs.path_join(vm_path, "ctrl.sh")
	render(tpls.VmScript, script_fpath, {
		name = vm.name,
		qemu_args = vm_args,
		qemu_bin_fpath = htt.fs.path_join(c.qemu_bin_dir_fpath, "qemu-system-" .. vm.arch),
		pid_fpath = pid_fpath,
		serial_fpath = serial_fpath,
		ssh_conf_fpath = ssh_conf_rel_fpath,
		login_timeout=vm.login_timeout,
		sync_enable=type(vm.sync) == "table" and #vm.sync > 0,
		sync=vm.sync
	})
end
