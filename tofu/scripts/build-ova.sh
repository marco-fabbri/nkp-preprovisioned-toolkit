#!/usr/bin/env bash
# Builds a minimal OVA (PVSCSI, vmxnet3, SATA CD-ROM) from a qcow2 cloud image,
# for the vSphere content library. Usage: build-ova.sh <qcow2> <name> <vmware_os_type> <out.ova>
set -euo pipefail
qcow="$1"; name="$2"; ostype="$3"; out="$4"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
qemu-img convert -O vmdk -o subformat=streamOptimized,adapter_type=lsilogic "$qcow" "$work/$name-disk1.vmdk"
# The top-level virtual-size of the image: a sed on the JSON would also match
# the nested format-specific entries.
capacity="$(qemu-img info --output=json "$qcow" | python3 -c 'import json, sys; print(json.load(sys.stdin)["virtual-size"])')"
size="$(wc -c < "$work/$name-disk1.vmdk" | tr -d ' ')"
cat > "$work/$name.ovf" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Envelope xmlns="http://schemas.dmtf.org/ovf/envelope/1" xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1" xmlns:rasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData" xmlns:vssd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData" xmlns:vmw="http://www.vmware.com/schema/ovf">
  <References><File ovf:href="$name-disk1.vmdk" ovf:id="file1" ovf:size="$size"/></References>
  <DiskSection><Info>Virtual disk</Info><Disk ovf:capacity="$capacity" ovf:capacityAllocationUnits="byte" ovf:diskId="vmdisk1" ovf:fileRef="file1" ovf:format="http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized"/></DiskSection>
  <NetworkSection><Info>Network</Info><Network ovf:name="VM Network"><Description>VM Network</Description></Network></NetworkSection>
  <VirtualSystem ovf:id="$name">
    <Info>NKP node image built from the distribution cloud image</Info>
    <Name>$name</Name>
    <OperatingSystemSection ovf:id="80" vmw:osType="$ostype"><Info>Guest OS</Info></OperatingSystemSection>
    <VirtualHardwareSection>
      <Info>Virtual hardware</Info>
      <System><vssd:ElementName>Virtual Hardware Family</vssd:ElementName><vssd:InstanceID>0</vssd:InstanceID><vssd:VirtualSystemType>vmx-19</vssd:VirtualSystemType></System>
      <Item><rasd:AllocationUnits>hertz * 10^6</rasd:AllocationUnits><rasd:ElementName>2 vCPU</rasd:ElementName><rasd:InstanceID>1</rasd:InstanceID><rasd:ResourceType>3</rasd:ResourceType><rasd:VirtualQuantity>2</rasd:VirtualQuantity></Item>
      <Item><rasd:AllocationUnits>byte * 2^20</rasd:AllocationUnits><rasd:ElementName>2048 MB</rasd:ElementName><rasd:InstanceID>2</rasd:InstanceID><rasd:ResourceType>4</rasd:ResourceType><rasd:VirtualQuantity>2048</rasd:VirtualQuantity></Item>
      <Item><rasd:ElementName>SCSI controller 0</rasd:ElementName><rasd:InstanceID>3</rasd:InstanceID><rasd:ResourceSubType>VirtualSCSI</rasd:ResourceSubType><rasd:ResourceType>6</rasd:ResourceType></Item>
      <Item><rasd:AddressOnParent>0</rasd:AddressOnParent><rasd:ElementName>Hard disk 1</rasd:ElementName><rasd:HostResource>ovf:/disk/vmdisk1</rasd:HostResource><rasd:InstanceID>4</rasd:InstanceID><rasd:Parent>3</rasd:Parent><rasd:ResourceType>17</rasd:ResourceType></Item>
      <Item><rasd:AutomaticAllocation>true</rasd:AutomaticAllocation><rasd:Connection>VM Network</rasd:Connection><rasd:ElementName>Network adapter 1</rasd:ElementName><rasd:InstanceID>5</rasd:InstanceID><rasd:ResourceSubType>VmxNet3</rasd:ResourceSubType><rasd:ResourceType>10</rasd:ResourceType></Item>
      <Item><rasd:ElementName>SATA controller 0</rasd:ElementName><rasd:InstanceID>6</rasd:InstanceID><rasd:ResourceSubType>vmware.sata.ahci</rasd:ResourceSubType><rasd:ResourceType>20</rasd:ResourceType></Item>
      <Item ovf:required="false"><rasd:AddressOnParent>0</rasd:AddressOnParent><rasd:AutomaticAllocation>false</rasd:AutomaticAllocation><rasd:ElementName>CD/DVD drive 1</rasd:ElementName><rasd:InstanceID>7</rasd:InstanceID><rasd:Parent>6</rasd:Parent><rasd:ResourceType>15</rasd:ResourceType></Item>
    </VirtualHardwareSection>
  </VirtualSystem>
</Envelope>
EOF
rm -f "$out"
# COPYFILE_DISABLE keeps macOS tar from adding AppleDouble "._*" entries for
# files with extended attributes: the vSphere provider would read one of them
# as the OVF. Other tar implementations ignore the variable.
COPYFILE_DISABLE=1 tar -cf "$out" -C "$work" "$name.ovf" "$name-disk1.vmdk"
