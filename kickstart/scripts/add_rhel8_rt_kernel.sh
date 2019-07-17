#!/bin/bash
subscription-manager repos --enable rhel-8-for-x86_64-rt-rpms
yum groupinstall -y RT
