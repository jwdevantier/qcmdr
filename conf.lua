-- Utility Code
---------------
local M = {}

local function flatten(lst)
	local res = {}
	local _flatten
	_flatten = function(l)
		for _, e in ipairs(l) do
			if type(e) == "table" then
				_flatten(e)
			else
				table.insert(res, e)
			end
		end
	end
	_flatten(lst)
	return res
end

M.map = function(t, fn)
	local ret = {}
	for i, e in ipairs(t) do
		ret[i] = fn(e)
	end
	return ret
end

-- Helper Functions
-------------------
local amd64Base = function(args)
	-- Many of my VMs use this template, so it's factored out
	return {
		"-nodefaults",
		"-machine", "q35,accel=kvm,kernel-irqchip=split",
		"-cpu", "host",
		"-smp", tostring(args.cores or 1),
		"-m", tostring(args.mem or 2048),
		"-device", "intel-iommu,intremap=on",
		"-device", "virtio-rng-pci"
	}
end

local virtioNet = function(args)
	-- virtio-backed net device with host->vm port forwarding support
	local function fwd(fwd)
		return string.format(
			"hostfwd=%s::%s-:%s",
			fwd.proto or "tcp",
			tostring(fwd.host),
			tostring(fwd.vm)
		)
	end

	local devArgs
	if args.fwd then
		local fwdArgs = table.concat(M.map(args.fwd, fwd), ",")
		devArgs = string.format("user,id=%s,%s", args.id, fwdArgs)
	else
		devArgs = string.format("user,id=%s", args.id)
	end

	return {
		"-netdev", devArgs,
		"-device", "virtio-net-pci,netdev=net0",
	}
end

local function trace(file)
	-- format a list of trace patterns
	return function(patterns)
		local result = {}
		for _, pattern in ipairs(patterns) do
			table.insert(result, "-trace")
			table.insert(result, string.format("enable=%s,file=%s", pattern, file))
		end
		return result
	end
end

-- The actual domain model
--------------------------
--
-- This is data which is basically the domain model, the configuration,
-- the truth I want to generate code from.
--
-- In this case, it reflects where QEMU binaries can be found,
-- global SSH settings and configuration entries for each VM to manage.

-- The directory containing qemu-system-<arch> binaries
M.qemu_bin_dir_fpath = "/home/jwd/repos/qemu/build"

-- These settings are written into a "Host *" entry, which applies to
-- all other host entries unless explicitly overridden.
M.ssh_conf_base = {
	Hostname = "localhost",
	ServerAliveInterval = 300,
	ServerAliveCountMax = 3,
	PubkeyAcceptedKeyTypes = "+ssh-rsa",
	HostKeyAlgorithms = "+ssh-rsa",
	-- Oddly, if I set 'User = root' in the 'Host *' section, that overrides the specific host section.
	StrictHostKeyChecking = "no",
	UserKnownHostsFile = "/dev/null",
}

-- Expose conf as list of VM's
M.vms = {}

table.insert(M.vms, {
	name = "livemig",
	arch = "x86_64",
	login_timeout = 20,
	ssh = {
		IdentityFile = "~/.ssh/id_rsa",
		Port = 2089,
		User = "root",
	},
	sync = {
		{
			source = "/home/jwd/repos/live-migration-tests/",
			dest = "~/tests",
			ignore_vcs = true,
			ignore = { "venv" },
			-- TODO: flags?
		}
	},
	args = {
		amd64Base { cores = 2, mem = 4096 },
		virtioNet {
			id = "net0",
			fwd = {
				{ host = 2089, vm = 22 },
			}
		},
		trace("/tmp/livemig.trace")({
			"pci_nvme_*",
			"-pci_nvme_update_*",
			"-pci_nvme_mmio_*",
			"-pci_nvme_irq_msix"
		}),
		"-drive", "id=boot,file=/home/jwd/repos/nix/nvmetestvm/overlay.img,format=qcow2,if=virtio,discard=unmap,media=disk",
		"-device", "nvme-subsys,id=nvme-subsys0",
		-- add CTRL 0 (I/O ctrl)
		"-device", "pcie-root-port,id=pcie_port0,chassis=1,slot=0",
		"-device", "nvme,id=nvme0,serial=deadbeef,bus=pcie_port0,subsys=nvme-subsys0,mdts=7",
		-- add CTRL 1 (Adm ctrl)
		"-device", "pcie-root-port,id=pcie_port1,chassis=1,slot=1",
		"-device", "nvme,id=nvme1,serial=deadbeef,bus=pcie_port1,subsys=nvme-subsys0,mdts=7,hmlms=on",
		"-drive", "id=nvm,file=/home/jwd/repos/nix/nvmetestvm/nvm_tst.img,format=raw,if=none,discard=unmap,media=disk",
		-- plug NVM NS into nvme0 (first ctrl)
		"-device", "nvme-ns,id=nvm,drive=nvm,bus=nvme0,nsid=1,logical_block_size=4096,physical_block_size=4096",
	}
})

table.insert(M.vms, {
	name = "loremail",
	arch = "x86_64",
	login_timeout = 15,
	ssh = {
		IdentityFile = "~/.ssh/id_rsa",
		Port = 3022,
		User = "mailuser",
	},
	args = {
		amd64Base { cores = 1, mem = 1024 },
		virtioNet {
			id = "net0",
			fwd = {
				{ host = 3022, vm = 22 },
				{ host = 3143, vm = 143 },
			},
		},
		"-display", '"none"',
		"-drive", "id=boot,file=/home/jwd/repos/nix-machines/os.img,format=qcow2,if=virtio,discard=unmap,media=disk",
	},
})

-- Domain Model Validation
--------------------------
-- This validates that the configuration (the model) adheres to
-- a certain shape. It's a declarative specification of how a valid
-- configuration should look.
-- We test at the boundaries to make it easier to write the templates themselves.
local function validVmName(str)
	local pattern = "^[%a_][%w_-]*$"
	local match = string.match(str, pattern)
	if match == nil then
		return string.format("'%s' invalid, must match '%s'", str, pattern)
	end
	return nil
end

local valid_vm_config = htt.is.table_with({
	name = htt.is.pred(validVmName, "VM name"),
	arch = htt.is.string,
	login_timeout = htt.is.number,
	args = htt.is.list_of(htt.is.string),
	sync = htt.is.optional(
		htt.is.list_of(
			htt.is.table_with({
				source = htt.is.string,
				dest = htt.is.string,
				ignore_vcs = htt.is.boolean,
				ignore = htt.is.optional(
					htt.is.list_of(htt.is.string)
				)
			})
		)
	),
	ssh = htt.is.all(
		htt.is.table_with({
			Port = htt.is.number,
			IdentityFile = htt.is.string,
			User = htt.is.string,
		}),
		htt.is.table_of(
			htt.is.string,
			htt.is.any(htt.is.string, htt.is.number)
		)
	)
})

local valid_config = htt.is.table_with({
	qemu_bin_dir_fpath = htt.is.string,
	vms = htt.is.list_of(valid_vm_config),
	ssh_conf_base = htt.is.table_of(
		htt.is.string,
		htt.is.any(htt.is.string, htt.is.number))
})



-- Validate the configuration
-----------------------------
-- Flatten VM args table, this makes it easier to write helper functions
-- which can just return tables of args.
--
-- This is the only transformation we do, but transforming the model early
-- to make downstream processing in templates easier is a good idea(tm).
for _, vm in ipairs(M.vms) do
	if vm.args ~= nil then
		vm.args = flatten(vm.args)
	end
end

-- Finally, validate the configuration.
-- (This is trigged on first import of the configuration module)
local ok, errs = valid_config(M)
if not ok then
	print("Error in configuration:")
	print(htt.str.stringify(errs))
	error("Error in configuration, see message above")
end

return M
