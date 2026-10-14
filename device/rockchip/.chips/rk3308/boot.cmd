setenv bootargs 'console=ttyS0,1500000n8 panic=10 consoleblank=0 root=/dev/mmcblk1p5 rootwait rootfstype=ext4 rw'
fatload mmc 0:4 ${kernel_addr_r} Image
fatload mmc 0:4 ${fdt_addr_r} rk3308bs-unihikerM10.dtb
booti ${kernel_addr_r} - ${fdt_addr_r}