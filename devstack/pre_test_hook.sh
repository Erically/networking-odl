#!/usr/bin/env bash

set -xe

# Drop a token that marks the build as coming from openstack infra
GATE_DEST=$BASE/new
DEVSTACK_PATH=$GATE_DEST/devstack

case "$ODL_RELEASE_BASE" in
    carbon-snapshot)
        ODL_RELEASE=carbon-snapshot-0.6.0
        ;;
    boron-snapshot)
        ODL_RELEASE=boron-snapshot-0.5.3
        ;;
    beryllium-snapshot)
        ODL_RELEASE=beryllium-snapshot-0.4.5
        ;;
    *)
        echo "Unknown ODL release base: $ODL_RELEASE_BASE"
        exit 1
        ;;
esac

case "$ODL_GATE_V2DRIVER" in
    v2driver)
        ODL_V2DRIVER=True
        ;;
    v1driver|*)
        ODL_V2DRIVER=False
        ;;
esac

case "$ODL_GATE_PORT_BINDING" in
    pseudo-agentdb-binding)
        ODL_PORT_BINDING_CONTROLLER=pseudo-agentdb-binding
        ;;
    legacy-port-binding)
        ODL_PORT_BINDING_CONTROLLER=legacy-port-binding
        ;;
    network-topology|*)
        ODL_PORT_BINDING_CONTROLLER=network-topology
        ;;
esac

case "$ODL_GATE_SERVICE_PROVIDER" in
    vpnservice)
        ODL_NETVIRT_KARAF_FEATURE=odl-neutron-service,odl-restconf-all,odl-aaa-authn,odl-dlux-core,odl-mdsal-apidocs,odl-netvirt-openstack
        ;;
    netvirt|*)
        ODL_NETVIRT_KARAF_FEATURE=odl-neutron-service,odl-restconf-all,odl-aaa-authn,odl-dlux-core,odl-mdsal-apidocs,odl-ovsdb-openstack
        ;;
esac
# add odl-neutron-logger for debugging
# odl-neutorn-logger has been introduced from boron cycle
case "$ODL_RELEASE_BASE" in
    carbon-snapshot|boron-snapshot)
        ODL_NETVIRT_KARAF_FEATURE=$ODL_NETVIRT_KARAF_FEATURE,odl-neutron-logger
        ;;
    *)
        ;;
esac

cat <<EOF >> $DEVSTACK_PATH/localrc

IS_GATE=True

# Set here the ODL release to use for the Gate job
ODL_RELEASE=${ODL_RELEASE}

# Set here which driver, v1 or v2 driver
ODL_V2DRIVER=${ODL_V2DRIVER}

# Set timeout in seconds for http client to ODL neutron northbound
ODL_TIMEOUT=60

# Set here which port binding controller
ODL_PORT_BINDING_CONTROLLER=${ODL_PORT_BINDING_CONTROLLER}

# Set here which ODL openstack service provider to use
ODL_NETVIRT_KARAF_FEATURE=${ODL_NETVIRT_KARAF_FEATURE}

# Switch to using the ODL's L3 implementation
ODL_L3=True

# TODO(yamahata): only for legacy netvirt
Q_USE_PUBLIC_VETH=True
Q_PUBLIC_VETH_EX=veth-pub-ex
Q_PUBLIC_VETH_INT=veth-pub-int
ODL_PROVIDER_MAPPINGS=${ODL_PROVIDER_MAPPINGS:-br-ex:\${Q_PUBLIC_VETH_INT}}

# Enable debug logs for odl ovsdb
ODL_NETVIRT_DEBUG_LOGS=True

RALLY_SCENARIO=${RALLY_SCENARIO}

# TODO(yamahata): remove this work around once the fix is released at pypi.
# https://bugs.launchpad.net/python-openstackclient/+bug/1652025
# https://review.openstack.org/#/c/417675/
# devstack fails with router creation with
# "TypeError: 'NoneType' object is not iterable"
# the issue is fixed with the above patch. Until the patch is released
# at pypi, use git master branch
LIBS_FROM_GIT=osc-lib

EOF

# delete private network to workaroud netvirt bug:
# https://bugs.opendaylight.org/show_bug.cgi?id=7456
if [[ "$DEVSTACK_GATE_TOPOLOGY" == "multinode" ]] ; then
    cat <<EOF >> $DEVSTACK_PATH/local.sh
#!/usr/bin/env bash

source $DEVSTACK_PATH/openrc admin
rid=\`neutron router-list | grep router1 | cut -f2 -d'|'\`
neutron router-gateway-clear \$rid
neutron router-port-list \$rid | grep subnet_id | cut -f4 -d'"' | xargs -I {} neutron router-interface-delete \$rid {}
neutron router-delete \$rid
neutron subnet-list | grep private | cut -f2 -d'|' | xargs neutron subnet-delete
neutron net-list | grep private | cut -f2 -d'|' | xargs neutron net-delete
EOF
    chmod 755 $DEVSTACK_PATH/local.sh
fi
