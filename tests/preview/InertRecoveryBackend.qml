import QtQuick
// Inert recording replica. No native plugin, IO, subprocess or network calls.
QtObject {
    property int status: 2
    property int blendStatus: 9
    property int blendCoreNodes: 5
    property bool blendRecoveryActive: false
    property bool useGeneratedConfig: false
    property string userConfig: "/synthetic/node.yaml"
    property string deploymentConfig: ""
    property string generatedUserConfigPath: "/synthetic/node.yaml"
    property string lastErrorMessage: ""
    property string primaryAddress: ""
    property string leaderKey: ""
    property string cpuUsage: ""
    property string ramUsage: ""
    property string diskUsage: ""
    property var calls: []
    signal faucetResult(bool ok, string message)
    function backupUserConfig() { calls.push("backupUserConfig"); return "backupUserConfig" }
    function channelDepositWithNotes() { calls.push("channelDepositWithNotes"); return "channelDepositWithNotes" }
    function checkBlendPortReachable() { calls.push("checkBlendPortReachable"); return "checkBlendPortReachable" }
    function claimLeaderRewards() { calls.push("claimLeaderRewards"); return "claimLeaderRewards" }
    function clearBlocks() { calls.push("clearBlocks"); return "clearBlocks" }
    function clearLeaderClaims() { calls.push("clearLeaderClaims"); return "clearLeaderClaims" }
    function clearProposals() { calls.push("clearProposals"); return "clearProposals" }
    function confirmRunning() { calls.push("confirmRunning"); return "confirmRunning" }
    function confirmStartFailed() { calls.push("confirmStartFailed"); return "confirmStartFailed" }
    function copyToClipboard() { calls.push("copyToClipboard"); return "copyToClipboard" }
    function declareBlendCore() { calls.push("declareBlendCore"); return "declareBlendCore" }
    function findTransactionInBlocks() { calls.push("findTransactionInBlocks"); return "findTransactionInBlocks" }
    function forceStopNow() { calls.push("forceStopNow"); return "forceStopNow" }
    function generateConfig() { calls.push("generateConfig"); return "generateConfig" }
    function getBalance() { calls.push("getBalance"); return "getBalance" }
    function getBlendDeclarations() { calls.push("getBlendDeclarations"); return "getBlendDeclarations" }
    function getBlendInfo() { calls.push("getBlendInfo"); return "getBlendInfo" }
    function getBlendLifecycle() { calls.push("getBlendLifecycle"); return "getBlendLifecycle" }
    function getBlendModeHistory() { calls.push("getBlendModeHistory"); return "getBlendModeHistory" }
    function getBlock() { calls.push("getBlock"); return "getBlock" }
    function getBlockTx() { calls.push("getBlockTx"); return "getBlockTx" }
    function getClaimableVouchers() { calls.push("getClaimableVouchers"); return "getClaimableVouchers" }
    function getCryptarchiaInfo() { calls.push("getCryptarchiaInfo"); return "getCryptarchiaInfo" }
    function getEpochHeights() { calls.push("getEpochHeights"); return "getEpochHeights" }
    function getLeaderClaims() { calls.push("getLeaderClaims"); return "getLeaderClaims" }
    function getNetworkInfo() { calls.push("getNetworkInfo"); return "getNetworkInfo" }
    function getNotes() { calls.push("getNotes"); return "getNotes" }
    function getPeerId() { calls.push("getPeerId"); return "getPeerId" }
    function getProposals() { calls.push("getProposals"); return "getProposals" }
    function getProposalsFull() { calls.push("getProposalsFull"); return "getProposalsFull" }
    function getRecoveryStatus() { calls.push("getRecoveryStatus"); return "getRecoveryStatus" }
    function getSdpFundingKey() { calls.push("getSdpFundingKey"); return "getSdpFundingKey" }
    function getTransaction() { calls.push("getTransaction"); return "getTransaction" }
    function pauseBlendRecovery() { calls.push("pauseBlendRecovery"); return "pauseBlendRecovery" }
    function pruneLogs() { calls.push("pruneLogs"); return "pruneLogs" }
    function recordEpochHeight() { calls.push("recordEpochHeight"); return "recordEpochHeight" }
    function refreshAccounts() { calls.push("refreshAccounts"); return "refreshAccounts" }
    function refreshBlendStatus() { calls.push("refreshBlendStatus"); return "refreshBlendStatus" }
    function regenerateNodeKeys() { calls.push("regenerateNodeKeys"); return "regenerateNodeKeys" }
    function repairBlendBinding() { calls.push("repairBlendBinding"); return "repairBlendBinding" }
    function requestFaucetFunds() { calls.push("requestFaucetFunds"); return "requestFaucetFunds" }
    function resetChainState() { calls.push("resetChainState"); return "resetChainState" }
    function resumeBlendRecovery() { calls.push("resumeBlendRecovery"); return "resumeBlendRecovery" }
    function saveKeystore() { calls.push("saveKeystore"); return "saveKeystore" }
    function startBlendRecovery() { calls.push("startBlendRecovery"); return "startBlendRecovery" }
    function startBlockchain() { calls.push("startBlockchain"); return "startBlockchain" }
    function stopBlockchain() { calls.push("stopBlockchain"); return "stopBlockchain" }
    function transferFunds() { calls.push("transferFunds"); return "transferFunds" }
    function withdrawBlendCore() { calls.push("withdrawBlendCore"); return "withdrawBlendCore" }
}
