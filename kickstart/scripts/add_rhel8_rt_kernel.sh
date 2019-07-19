#!/bin/bash
subscription-manager repos --enable rhel-8-for-x86_64-rt-rpms
yum groupinstall -y RT

# set tuned profile
cmdline_realtime="intel_pstate=disable nosoftlockup nmi_watchdog=0 audit=0 mce=off kthread_cpus=0 irqaffinity=0 skew_tick=1 processor.max_cstate=1 idle=poll intel_idle.max_cstate=0 intel_pstate=disable intel_iommu=off"

sed -i 's|^cmdline_realtime.*|cmdline_realtime='"${cmdline_realtime}"'|' /usr/lib/tuned/realtime/tuned.conf
tuned-adm profile realtime
