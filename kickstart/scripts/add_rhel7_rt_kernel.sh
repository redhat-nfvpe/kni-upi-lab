#!/bin/bash
subscription-manager repos --enable rhel-7-server-rt-rpms
yum groupinstall -y RT
