# Slack Messaging Improvements

## Overview
The existing vSphere monitoring scripts have been updated to provide better organized and more readable Slack messages. Instead of sending individual messages for each piece of information, the scripts now consolidate data and send well-formatted summary messages.

## Key Improvements Made

### 1. **Consolidated Messaging**
- **Before**: Each CNS volume count and storage policy count was sent as a separate Slack message
- **After**: All data for a vCenter is collected and sent in a single, organized message

### 2. **Better Message Structure**
- **Summary headers** with total counts and entity counts
- **Organized breakdowns** by datastore/vCenter
- **Consistent formatting** using Slack markdown and emojis

### 3. **Reduced Message Volume**
- **Before**: Multiple messages per vCenter per run
- **After**: One message per vCenter per run (or one consolidated message for all vCenters)

### 4. **Improved Readability**
- **Emojis** for visual categorization (:package: for volumes, :gear: for policies, :warning: for alarms)
- **Bold text** for important numbers and headers
- **Bullet points** for organized lists
- **Clear sections** separating different types of information

## Scripts Updated

### `scripts/cnsvols.ps1` - CNS Volume Monitoring
- **Before**: Sent individual message for each datastore's volume count
- **After**: Collects all volume counts per vCenter and sends one summary message
- **Format**: 
  ```
  :package: CNS Volumes Summary - [vCenter]
  Total Volumes: [total] | Datastores: [count]
  
  Datastore Breakdown:
  • [datastore1]: [count] volumes
  • [datastore2]: [count] volumes
  ```

### `scripts/spbm.ps1` - Storage Policy Management
- **Before**: Sent individual message for each vCenter's storage policy count
- **After**: Collects all policy counts and sends one summary message for all vCenters
- **Format**:
  ```
  :gear: Storage Policy Summary
  Total Policies: [total] | vCenters: [count]
  
  Policy Count by vCenter:
  • [vcenter1]: [count] policies
  • [vcenter2]: [count] policies
  ```

### `scripts/vcenteralarms.ps1` - vCenter Alarm Monitoring
- **Before**: Sent individual message for each vCenter's alarms
- **After**: Collects all alarm information and sends one comprehensive health status message
- **Format**:
  ```
  :warning: vCenter Health Status - Active Alarms
  Total Alarms: [total] | Critical: [count] | Warning: [count]
  
  Alarms by vCenter:
  [vcenter1]:
    :fire: CRITICAL: [alarm_name] on [entity]
    :warning: WARNING: [alarm_name] on [entity]
  ```

### `scripts/esxialerts.ps1` - ESXi Host Health Monitoring
- **Before**: Sent individual message for each vCenter with ESXi alerts
- **After**: Collects all ESXi alerts and sends one consolidated health status message
- **Format**:
  ```
  :warning: ESXi Health Status - Active Alerts
  Total Alerts: [total] | vCenters with Issues: [count]
  
  Alerts by vCenter:
  [vcenter1]:
    • [host_name] [sensor_name]
  ```

### `scripts/kubevols.ps1` - Kubernetes Volume Cleanup
- **Before**: Sent individual message for each vCenter's kubevol count
- **After**: Collects all kubevol counts and sends one summary message for all vCenters
- **Format**:
  ```
  :floppy_disk: Kubernetes Volumes Summary
  Total Kubevols: [total] | vCenters: [count]
  
  Kubevol Count by vCenter:
  • [vcenter1]: [count] kubevols
  • [vcenter2]: [count] kubevols
  ```

### `scripts/orphanvms.ps1` - Orphan VM Cleanup
- **Before**: Sent individual message for each vCenter with orphaned VMs
- **After**: Collects all orphaned VM information and sends one consolidated status message
- **Format**:
  ```
  :ghost: Orphan VM Status - Cleanup Required
  Total Orphaned VMs: [total] | vCenters with Orphans: [count]
  
  Orphaned VMs by vCenter:
  [vcenter1]:
    • [vm_name1]
    • [vm_name2]
  ```

### `scripts/foldertag.ps1` - Folder and Tag Cleanup
- **Before**: Sent individual message for each vCenter with folder/tag counts
- **After**: Collects all folder/tag counts and sends one summary message for all vCenters
- **Format**:
  ```
  :file_folder: Folder and Tag Cleanup Summary
  Total Folders: [total] | Total Tags: [total] | vCenters: [count]
  
  Counts by vCenter:
  • [vcenter1]: [folder_count] folders, [tag_count] tags
  • [vcenter2]: [folder_count] folders, [tag_count] tags
  ```

### `scripts/rp.ps1` - Resource Pool Cleanup
- **Before**: Sent individual message for each vCenter with resource pool count
- **After**: Collects all resource pool counts and sends one summary message for all vCenters
- **Format**:
  ```
  :pools: Resource Pool Cleanup Summary
  Total Resource Pools: [total] | vCenters: [count]
  
  Resource Pool Count by vCenter:
  • [vcenter1]: [count] resource pools
  • [vcenter2]: [count] resource pools
  ```

### `scripts/lockout.ps1` - Account Lockout Monitoring
- **Before**: Sent individual message for each vCenter with locked accounts
- **After**: Collects all account lockout information and sends one consolidated status message
- **Format**:
  ```
  :warning: Account Lockout Status - Action Required
  Total Locked Accounts: [total] | vCenters with Lockouts: [count]
  
  Locked Accounts by vCenter:
  [vcenter1]:
    • [account1]
    • [account2]
  ```

## Benefits

1. **Reduced Noise**: Fewer messages in Slack channels
2. **Better Organization**: Related information grouped together
3. **Easier Scanning**: Quick overview with summary numbers
4. **Consistent Format**: Uniform appearance across all script outputs
5. **Actionable Information**: Clear totals and breakdowns for monitoring

## Implementation Details

- Each script now collects data in memory before sending messages
- Messages are formatted using Slack's markdown syntax
- Emojis provide visual categorization
- Error messages are also improved with consistent formatting
- All scripts maintain their original functionality while improving output

## Intelligent Alerting

### Account Lockout Script (`lockout.ps1`)
The lockout script runs every minute as a cronjob and now implements **intelligent alerting** without requiring persistent storage:

- **Only sends Slack messages when there are actual changes** in account lockout status
- **Uses hash-based change detection** to compare current status with previous run
- **Sends immediate alerts** for any status changes (new lockouts, unlocks, etc.)
- **Always sends error messages** regardless of frequency for critical issues
- **Includes timestamp** in messages for tracking when status was last checked

**How it works:**
1. **Hash Generation**: Creates a unique hash of current lockout status
2. **Change Detection**: Compares current hash with previous run's hash
3. **Immediate Alerts**: Sends notification whenever lockout status changes
4. **No Spam**: Skips notification when status is unchanged

### Orphan VM Script (`orphanvms.ps1`)
The orphan VM script also implements **intelligent alerting** to prevent spam:

- **Only sends Slack messages when there are actual changes** in orphaned VM status
- **Uses hash-based change detection** to compare current status with previous run
- **Sends immediate alerts** when new orphaned VMs are detected or cleaned up
- **Always sends error messages** regardless of frequency for critical issues
- **Includes timestamp** in messages for tracking when status was last checked

**How it works:**
1. **Hash Generation**: Creates a unique hash of current orphaned VM status
2. **Change Detection**: Compares current hash with previous run's hash
3. **Immediate Alerts**: Sends notification whenever orphaned VM status changes
4. **No Spam**: Skips notification when status is unchanged

This prevents spam while ensuring important changes are communicated immediately, without requiring persistent storage between cronjob runs. Perfect for CI environments where lockouts and orphaned VMs can happen at any time and need immediate attention.

## Future Enhancements

- Consider implementing Slack Block Kit for even richer formatting
- Add timestamp grouping for multiple runs
- Implement message threading for related alerts
- Add color coding for different severity levels
