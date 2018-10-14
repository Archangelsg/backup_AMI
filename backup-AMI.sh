#!/bin/bash

# This is a script for backuping running EBS-backed instances.
# Run this script on the instance to be backuped

INSTANCE_ID="Your_Instance_Id"
DESCRIPTION="This AMI has been created from the instance: $INSTANCE_ID"

PERIOD_OF_ROTATION="1 week ago"
ROTATION_DATE=`date -d "$PERIOD_OF_ROTATION" +%Y.%m.%d`

UNIQ_ID="name_instance+ip_instance"

##########################################################################################

# Flushing file system buffers
flushing_buffers(){
    for i in 1 2 3 4 5; do
        sync && sleep 1
    done
}
#flushing_buffers

# Creating a new AMI from the current running instance
echo "----- Start at `date`"
echo "Creating a new AMI from the current running instance \"$INSTANCE_ID\":"
echo "..."
AMI=`aws ec2 create-image --name="backup-$(date +%Y.%m.%d-%H-%M)-$UNIQ_ID" --description="$DESCRIPTION" --no-reboot --instance-id $INSTANCE_ID | awk '{print $2}' | tr -d \" `
while [ "$STATE1" != "available" ]; do
    DESCRIBE_AMI=`aws ec2 describe-images --image-ids $AMI --query "Images[*].State" | tr -d \"[]`
    STATE1=`echo $DESCRIBE_AMI | grep -v "^$"`
    echo $STATE1
    STATE2=`echo $DESCRIBE_AMI | grep "does not exist"`
    if [ "$STATE1" = "failed" -o -n "$STATE2" ]; then
         aws ec2 deregister-image $AMI 2> /dev/null
        flushing_buffers
        AMI=`aws ec2 create-image --name="backup-$(date +%Y.%m.%d-%H-%M)-$UNIQ_ID" --description="$DESCRIPTION" --no-reboot --instance-id $INSTANCE_ID | awk '{print $2}' tr -d \"`
    fi
    sleep 15
done
echo "Congratulations! A new AMI \"$AMI\" has just been registered successfully."
echo "----- Stop  at `date`"
echo ""

# Deleting AMIs older then $PERIOD_OF_ROTATION
EC2_DESCRIBE_IMAGES_ALL=`aws ec2 describe-images --query "Images[*].Name" | tr -d \"[]`
EC2_DESCRIBE_IMAGES_BKP=`echo "$EC2_DESCRIBE_IMAGES_ALL" | grep -E "backup-[[:alnum:]]{4}\.[[:alnum:]]{2}\.[[:alnum:]]{2}-[[:alnum:]]{2}-[[:alnum:]]{2}-$UNIQ_ID"`
for DATE in `echo "$EC2_DESCRIBE_IMAGES_BKP" | sed 's/^.*\/backup\-\(....\...\...\)\-.*$/\1/' | sort | uniq`; do
    if [ `echo $DATE | tr -d ".|-" | awk '{print substr($0,7,8)}'` -le `echo $ROTATION_DATE | tr -d ".|-"` ]; then
        echo "----- Deleting old backups for \"$DATE\""
        echo "----- Start at `date`"
        for AMI_ID in `echo "$EC2_DESCRIBE_IMAGES_BKP" | grep $DATE |tr -d \,`; do
            echo "AMI_ID="$AMI_ID
            AMI_PARAMETERS=`aws ec2 describe-images --filters Name=name,Values=$AMI_ID --query Images[*].ImageId | tr -d \"[]`
            echo "AMI_PARAMETERS="$AMI_PARAMETERS

            AMI_SNAPSHOTS=`aws ec2 describe-images --image-ids $AMI_PARAMETERS --query Images[*].BlockDeviceMappings[*].Ebs.SnapshotId |  tr -d \"[],`

            echo "AMI_SNAPSHOT="$AMI_SNAPSHOTS
            echo "-------------------------------"
            echo "Deregistering AMI: $AMI_ID"
            aws ec2 deregister-image --image-id $AMI_PARAMETERS
            echo "Done..."
            for SNAPSHOT in $AMI_SNAPSHOTS; do
                echo ""
                echo "Deleting the snapshot: $SNAPSHOT"
                aws ec2 delete-snapshot --snapshot-id $SNAPSHOT
                echo "Done..."
            done
            echo "-------------------------------"
        done
        echo "----- Stop  at `date`"
        echo ""
    fi
done
