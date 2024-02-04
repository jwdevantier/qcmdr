
(defun vm-x86-base (&key (mem 2048) (cores 1))
  "define the basics of a x86-64 machine"
  (list "-nodefaults"
        "-machine" "q35,accel=kvm,kernel-irqchip=split"
        "-cpu" "host"
        "-smp" cores
        "-m" mem
        "-device" "intel-iommu,intremap=on"
        "-device" "virtio-rng-pci"))

(defvar conf
  `(:qemu-bin-dir #p"~/repos/qemu/build"
    ;; NOTE: these keys are unnecessary, but illustrate a point. For both
    ;;       here and inside :ssh-conf of each VM you can specify ANY option
    ;;       you might want to write in your SSH hosts configuration file
    ;;       (~/.ssh/config), see `man ssh_config` for your options.
    ;;
    ;;       For any setting simply rewrite it from Pascal notation
    ;;       to kebab-case (snake-case, but with hyphens instead of underscore).
    ;;       That is, 'StrictHostKeyChecking' becomes ':strict-host-key-checking'.
    ;;       The lead colon (:) is there to turn the identifier into a keyword,
    ;;       a lisp data-type (actually a type of symbol).
    ;; TODO: empty of keys later on - none of this should be set...
    ;;       - maybe set the defaults in here, as an example.
    :ssh-conf (:server-alive-interval 300
               :server-alive-count-max 3
               :pubkey-accepted-key-types "+ssh-rsa"
               :host-key-algorithms "+ssh-rsa")
    :vms
    (:fedoravm (:arch "x86_64"
                ;; NOTE: for now there is no support for building the VM image, so disregard this argument
                :builder :none
                :ssh-conf (;; see note in global :ssh-conf
                           :user "root"
                           :port 4200)
                :sync ("/tmp/hullo-source" (:dest "~/hullo-sink"
                                            :ignore-vcs? t
                                            :ignore ("venv")
                                            :flags ()))
                ;; Advanced trick, we are in a Lisp symbol context and we use comma-splice (,@)
                ;; to evaluate the form '(vm-x86-base :cores 2)' (we call the function defined above)
                ;; and SPLICE the contents of the list it returns into this list. Think of it as flattening
                ;; the list from (list (list a b c) d e f) to (list a b c d e f).
                ;;
                ;; You *may* dislike this, but it demonstrates that you can do whatever you please to
                ;; factor out repetitive parts of your configuration.
                :args (,@(vm-x86-base :cores 2)
                       ;; Notice how we pass a list of raw arguments - nothing new to learn, write what you need
                       "-netdev" "user,id=net0,hostfwd=tcp::4200-:22"
                       "-device" "virtio-net-pci,netdev=net0"
                       "-drive" "file=/home/jwd/fedora.qcow2,format=qcow2,if=virtio"))
     :nvme (:arch "x86_64"
            :builder :none
            :ssh-conf (:user "root"
                       :port 2089
                       :identity-file "~/.ssh/id_rsa")
            :sync ("/home/jwd/repos/project-tests/" (:dest "~/tests"
                                                     :ignore-vcs? t
                                                     :ignore ("venv")
                                                     :flags nil))
            :args (,@(vm-x86-base :cores 2 :mem 4096)
                   "-netdev" "user,id=net0,hostfwd=tcp::2089-:22,hostfwd=tcp::8888-:8888"
                   "-device" "virtio-net-pci,netdev=net0"
                   "-drive" "id=boot,file=/home/jwd/repos/nix/nvmetestvm/overlay.img,format=qcow2,if=virtio,discard=unmap,media=disk"
                   "-device" "pcie-root-port,id=pcie_root_port0,chassis=1,slot=0"
                   "-device" "nvme,id=nvme0,serial=deadbeef,bus=pcie_root_port0,mdts=7"
                   "-drive" "id=nvm,file=/home/jwd/repos/nix/nvmetestvm/nvm_tst.img,format=raw,if=none,discard=unmap,media=disk"
                   "-device" "nvme-ns,id=nvm,drive=nvm,bus=nvme0,nsid=1,logical_block_size=4096,physical_block_size=4096")))))
