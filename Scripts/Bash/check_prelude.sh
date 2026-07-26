cat << 'EOF' > /usr/local/bin/check_prelude.sh
# above copies file to the location this should the below is supposed to and i hope  catch if a pod is  #started but not i.e. postgress 1/2
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
UNREADY_PODS=$(kubectl get pods -n "${NAMESPACE}" -o jsonpath='{range .items[*]}{@.metadata.name}{"\t"}{@.status.phase}{"\t"}{range @.status.containerStatuses[*]}{@.ready}{" "}{end}{"\n"}{end}' 2>/dev/null | grep -v 'false' | awk '{print $1}' || true)

# Combine both failures
FAILED_PODS=""
if [ -n "$NOT_RUNNING_PHASE" ]; then
    FAILED_PODS="${FAILED_PODS}--- Pods with Non-Running Phase ---\n${NOT_RUNNING_PHASE}\n\n"
fi

# Filter for pods where any container ready state is false
CONTAINER_FAILURES=$(kubectl get pods -n "${NAMESPACE}" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.containerStatuses[*]}{.name}{"="}{.ready}{" "}{end}{"\n"}{end}' | grep "false" || true)

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