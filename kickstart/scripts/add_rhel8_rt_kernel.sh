#!/bin/bash
subscription-manager repos --enable rhel-8-for-x86_64-rt-rpms
yum groupinstall -y RT

cat <<EOL > /etc/tuned/realtime-variables.conf
isolated_cores=${RT_TUNED_ISOLATE_CORES}
hugepage_size_default=${RT_TUNED_HUGEPAGE_SIZE_DEFAULT}
hugepage_size=${RT_TUNED_HUGEPAGE_SIZE}
hugepage_num=${RT_TUNED_HUGEPAGE_NUM}
EOL

cmdline_realtime="+isolcpus=\${isolated_cores} intel_pstate=disable nosoftlockup nmi_watchdog=0 audit=0 mce=off kthread_cpus=0 irqaffinity=0 skew_tick=1 processor.max_cstate=1 idle=poll intel_idle.max_cstate=0 intel_pstate=disable intel_iommu=off default_hugepagesz=\${hugepage_size_default} hugepagesz=\${hugepage_size} hugepages=\${hugepage_num} nohz=on nohz_full=\${isolated_cores} rcu_nocbs=\${isolated_cores}"

sed -i 's|^cmdline_realtime.*|cmdline_realtime='"${cmdline_realtime}"'|' /usr/lib/tuned/realtime/tuned.conf
tuned-adm profile realtime

