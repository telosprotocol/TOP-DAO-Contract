// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./CrossDaoCommon.sol";
import "../common/Utils.sol";
import "./IDaoSetting.sol";

abstract contract ICrossGovernance{
    using CrossDaoCommon for bytes;
    using ECDSA for bytes32;

    event ProposalExecuted(
        uint256 proposalID,
        bytes   proposalInfo
    );

    function _decodeLog(bytes memory log) internal pure returns(address contractAddress, bytes32[] memory topics, bytes memory action) {
        (contractAddress, topics, action) = abi.decode(log, (address,bytes32[],bytes));
    }

    function _verify(uint256 term, bytes32 hash, bytes[] memory signs) internal view returns(bool) {
        uint256 count;
        for (uint256 i = 0; i < signs.length; ++i) {
            (address _signer, ) = hash.tryRecover(signs[i]);
            require(_signer != address(0), "invalid signer");
            require(isVoterExist(term, _signer), "invalid voter");
            count++;
        }

        if (count < _quorum(term)) {
            return false;
        }

        return true;
    }

    function _checkCrossDaoHeader(uint256 fromChainID, uint256 toChainID, address fromAddress) internal virtual;
    
    function _changeNonce(uint256 chainID, uint256 newNonce, uint256 currentTerm) internal virtual;
    
    function _changeTerm(uint256 newTerm) internal virtual;
    
    function _quorum(uint256 _term) internal view virtual returns (uint256);
    
    function _executor() internal view virtual returns (address);

    function _isAdmin() internal view virtual returns (bool);
    
    function isVoterExist(uint256 term, address voter) public view virtual returns (bool);
    
    function proposalProcessor(uint256 kindId) public virtual returns(address);

    function bindProposalProcessor(uint256 kindId, address token) public virtual;

    function execute(bytes calldata log) public {
        (address contractAddress, bytes32[] memory topics, bytes memory action) = _decodeLog(log);
        require(topics.length == 1, "invalid num of topics");
        require(topics[0] == CrossDaoCommon.CrossDaoBridgeEventID, "invalid topic");
        
        CrossDaoBridge memory bridge = action.decodeCrossDaoBridge();
        require(bridge.from == contractAddress, "invalid from contract");
        uint256 proposalID = uint256(keccak256(bridge.proposalInfo));
        require(proposalID == bridge.proposalID, "invalid proposal");
        
        CrossDaoTx memory dao = bridge.proposalInfo.decodeCrossDaoTx();
        require(dao.kindId == bridge.kindId, "invalid governor type");
        bytes32 signed = (keccak256(abi.encode(bridge.from, proposalID, VoteType.For))).toEthSignedMessageHash();
        require(_verify(dao.termID, signed, bridge.signs), "invalid signature");
        _checkCrossDaoHeader(dao.fromChainID, dao.toChainID, bridge.from);

        _changeNonce(dao.toChainID, dao.nonce, dao.termID);
        if (bridge.kindId == 0) {
            require(_isAdmin(), "not admin");
            bytes4 actionId = bytes4(Utils.bytesToBytes32(dao.action));
            if (actionId == IDaoSetting.changeVoters.selector ||
                actionId == IDaoSetting.updateVotingRatio.selector ||
                actionId == IDaoSetting.setVotingDelay.selector ||
                actionId == IDaoSetting.bindNeighborChains.selector) {
                string memory errorMessage = "fail to execute governor";
                (bool success, bytes memory returnData) = address(this).call(dao.action);
                Address.verifyCallResult(success, returnData, errorMessage);
            }
        } else if (bridge.kindId == 1) {
        } else if (bridge.kindId == 2) {
            bytes4 actionId = bytes4(Utils.bytesToBytes32(dao.action));
            if (actionId == ICrossGovernance.bindProposalProcessor.selector) {
                string memory errorMessage = "fail to execute governor";
                (bool success, bytes memory returnData) = address(this).call(dao.action);
                Address.verifyCallResult(success, returnData, errorMessage);
            }
        } else {
            string memory errorMessage = "undercall reverted without message";
            address token = proposalProcessor(bridge.kindId);
            if (token.code.length > 0) {
                (bool success, bytes memory returnData) = token.call(dao.action);
                Address.verifyCallResult(success, returnData, errorMessage);
            }
        }

        emit ProposalExecuted(proposalID, bridge.proposalInfo);
    }
}