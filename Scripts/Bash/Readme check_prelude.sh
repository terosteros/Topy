README: Prelude Namespace Pod Health Monitoring & Email Alerts
This guide details how to install, manually run, and schedule automated health checks for Kubernetes pods in the prelude namespace on VMware Aria Automation (vRA) and vRealize Orchestrator (vRO) appliances.
Overview
The script (check_prelude.sh) performs a deep inspection of all pods running in the prelude namespace. It checks for two distinct failure modes:
1.	Unhealthy Pod Phases: Pods in states like CrashLoopBackOff, Pending, Error, or Terminating.
2.	Unready Containers: Pods in a Running state where internal container readiness checks fail (e.g., 0/1 or 1/2 Ready).
If any issues are detected, an alert email is dispatched via curl through your designated SMTP relay.
Installation & Setup
Run this command block directly on your vRA/vRO appliance as root to create the script file and make it executable:
Bash
cat << 'EOF' > /usr/local/bin/check_prelude.sh
#!/usr/bin/env bash
#
# Helper script to monitor pods in 'prelude' and email alerts via curl (SMTP)

set -e

# Configuration
NAMESPACE="prelude"
MAIL_RELAY="mail.tits.com.au"
RECIPIENT="sasha.wanker@gmail.com"
SENDER="vra-alerts@$(hostname -f 2>/dev/null || echo "vra-node.local")"

# Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 1. Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}[ERROR] kubectl command not found.${NC}"
    exit 1
fi

echo -e "${BLUE}=====================================================${NC}"
echo -e "${BLUE} Fetching Pods Status in Namespace: ${YELLOW}${NAMESPACE}${NC}"
echo -e "${BLUE}=====================================================${NC}"

# 2. Get full pod list
POD_STATUS=$(kubectl get pods -n "${NAMESPACE}" -o wide)
echo "$POD_STATUS"

echo ""

# 3. Check for pods that are NOT in Running/Succeeded phase
NOT_RUNNING_PHASE=$(kubectl get pods -n "${NAMESPACE}" --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null || true)

# 4. Check for pods that are 'Running' but have UNREADY containers (e.g., READY 0/1 or 1/2)
CONTAINER_FAILURES=$(kubectl get pods -n "${NAMESPACE}" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.containerStatuses[*]}{.name}{"="}{.ready}{" "}{end}{"\n"}{end}' 2>/dev/null | grep "false" || true)

# Combine both failure types
FAILED_PODS=""
if [ -n "$NOT_RUNNING_PHASE" ]; then
    FAILED_PODS="${FAILED_PODS}--- Pods with Non-Running Phase ---\n${NOT_RUNNING_PHASE}\n\n"
fi

if [ -n "$CONTAINER_FAILURES" ]; then
    FAILED_PODS="${FAILED_PODS}--- Pods with Unready Containers (0/1 or 1/2 Ready) ---\n${CONTAINER_FAILURES}\n"
fi

# 5. Send Email if ANY issues were detected
if [ -n "$FAILED_PODS" ]; then
    echo -e "${RED}⚠️ Warning: Unhealthy Pods or Unready Containers Detected! Sending alert via curl...${NC}"
    
    SUBJECT="[ALERT] vRA/vRO Prelude Pod Failures on $(hostname)"
    
    curl --url "smtp://${MAIL_RELAY}:25" \
      --mail-from "${SENDER}" \
      --mail-rcpt "${RECIPIENT}" \
      --upload-file - <<MAIL_DATA
From: ${SENDER}
To: ${RECIPIENT}
Subject: ${SUBJECT}

The following issues were detected in namespace '${NAMESPACE}':

${FAILED_PODS}

Full Pod Overview:
${POD_STATUS}
MAIL_DATA

    echo -e "${GREEN}✓ Alert email successfully relayed to ${RECIPIENT}${NC}"
else
    echo -e "${GREEN}✓ All pods and containers in namespace '${NAMESPACE}' are healthy and ready! No email needed.${NC}"
fi
EOF

chmod +x /usr/local/bin/check_prelude.sh
Manual Execution & Verification
To run a manual check at any time, execute the script directly from your terminal:
Bash
/usr/local/bin/check_prelude.sh
Expected Terminal Output
•	All Pods Healthy: Displays the full pod overview table followed by:
Plaintext
✓ All pods and containers in namespace 'prelude' are healthy and ready! No email needed.
•	Failure Detected: Highlights the specific unready containers or phase failures in red and attempts the email relay:
Plaintext
⚠️ Warning: Unhealthy Pods or Unready Containers Detected! Sending alert via curl...
✓ Alert email successfully relayed to sasha.wanker@gmail.com
Automated Schedule Setup (Cron)
To schedule the health check to run automatically twice daily at 7:00 AM and 4:00 PM:
1.	Open root's system crontab editor:
Bash
sudo crontab -e
2.	Add this schedule line at the very bottom of the file:
Code snippet
0 7,16 * * * KUBECONFIG=/etc/kubernetes/admin.conf /usr/local/bin/check_prelude.sh > /dev/null 2>&1
3.	Save and exit the editor.
Schedule Breakdown
Cron Field	Value	Meaning
Minute	0	Top of the hour
Hour	7,16	7:00 AM and 4:00 PM (16:00)
Day of Month	*	Every day
Month	*	Every month
Day of Week	*	Every day of the week
Environment Variable	KUBECONFIG=/etc/kubernetes/admin.conf	Passes cluster permissions to non-interactive cron jobs
4.	Verify the cron entry is active:
Bash
sudo crontab -l

