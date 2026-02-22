# Azure Storage Account Migration  
**From Azure Account-1 to Azure Account-2**

This document describes how to migrate data from a Storage Account in one Azure account to another Azure account using Azure Portal (UI) and AzCopy.

---

## Prerequisites
- Access to both source and destination Azure accounts
- Azure Storage Account available in source account
- Azure CLI / AzCopy installed on local machine

AzCopy download:
https://learn.microsoft.com/azure/storage/common/storage-use-azcopy-v10

---

## Step 1: Install AzCopy
### For macOS: Using Homebrew (Recommended)
```bash
brew update
brew install azcopy 
```
#### Verify

```bash
azcopy --version
```

### For Ubuntu
```bash
curl -L https://aka.ms/downloadazcopy-v10-mac -o azcopy.tar.gz
tar -xvf azcopy.tar.gz
sudo mv azcopy*/azcopy /usr/local/bin/
```
#### Verify

```bash
azcopy --version
```
---

## Step 2: Create Storage Account and Container in Destination Account
1. Login to **Destination Azure Account**
2. Go to **Storage Accounts**
3. Click **Create**
4. Select:
   - Subscription
   - Resource Group
   - Storage Account Name
   - Region
   - Performance (Standard recommended)
5. Click **Review + Create**

### Create Container
1. Open the newly created **Storage Account**
2. Go to **Data Storage → Containers**
3. Click **+ Container**
4. Enter container name
5. Set Public access level as required
6. Click **Create**

---

## Step 3: Generate SAS URL for Destination Container
1. Open **Destination Storage Account**
2. Go to **Containers**
3. Open the destination container
4. Click **Generate SAS**
5. Set:
   - Permissions: Read, Write, List, Create
   - Expiry time (ensure enough duration)
6. Click **Generate SAS token and URL**
7. Copy the **Container SAS URL**

---

## Step 4: Generate SAS URL for Source Container
1. Login to **Source Azure Account**
2. Open **Source Storage Account**
3. Go to **Containers**
4. Select the source container
5. Click **Generate SAS**
6. Set:
   - Permissions: Read, List
   - Expiry time
7. Click **Generate SAS token and URL**
8. Copy the **Container SAS URL**

---

## Step 5: Run AzCopy Command
Use the following command to start migration:

```bash
azcopy copy "<SOURCE_CONTAINER_SAS_URL>" "<DESTINATION_CONTAINER_SAS_URL>" --recursive=true
