// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

struct Signature{
    bytes32 r;
    bytes32 s;
    uint8 v;
}

struct CrossDaoTx{
    uint8       kindId;
    uint256     fromChainID;
    uint256     toChainID;
    uint256     termID;
    uint256     nonce;
    bytes       action;
    bytes32     descriptionHash;
}

struct CrossDaoBridge{
    address from;
    uint256 proposalID;
    uint8   kindId;
    bytes   proposalInfo;
    bytes[] signs;
}

enum ProposalState {
    Pending,
    Active,
    Canceled,
    Defeated,
    Succeeded,
    Queued,
    Expired,
    Executed
}

enum VoteType {
    Against,
    For,
    Abstain
}

library CrossDaoCommon {
    event CrossDaoProposalCreated(
        uint256 proposalId,
        address proposer,
        uint8   kindId,
        bytes   action
    );

    event CrossDaoVoteCast(
        address indexed voter,
        uint256 proposalId,
        uint8   support,
        uint256 weight
    );

    event CrossDaoBridgeEvent(
        address from,
        uint256 proposalID,
        uint8   kindId,
        bytes   proposalInfo,
        bytes[] signs
    );

    bytes32 constant public CrossDaoBridgeEventID = 0x5a7d7afefe941f9424d2ec716afee6eada95b6e28820a13ecbcb183d226d6cac;

    function decodeCrossDaoTx(bytes memory data) internal pure returns (CrossDaoTx memory dao) {
        (dao.kindId, dao.fromChainID, dao.toChainID, dao.termID, dao.nonce, dao.action, dao.descriptionHash)
            = abi.decode(data,(uint8,uint256,uint256,uint256,uint256,bytes,bytes32));
    }

    function encodeCrossDaoTx(
        uint8   kindId,
        uint256 fromChainID,
        uint256 toChainID,
        uint256 termID,
        uint256 nonce,
        bytes memory action,
        bytes32 descriptionHash
    ) internal pure returns (bytes memory dao) {
        return abi.encode(kindId, fromChainID, toChainID, termID, nonce, action, descriptionHash);
    }

    function decodeCrossDaoBridge(bytes memory data) internal pure returns (CrossDaoBridge memory dao) {
        (dao.from, dao.proposalID, dao.kindId, dao.proposalInfo, dao.signs) 
            = abi.decode(data,(address,uint256,uint8,bytes,bytes[]));
    }
}