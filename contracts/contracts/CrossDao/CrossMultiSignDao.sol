// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/governance/utils/IVotes.sol";
import "@openzeppelin/contracts/utils/Timers.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./CrossDaoCommon.sol";
import "./IDaoSetting.sol";
import "../common/Utils.sol";

/** 
 * kind id = 0 means governor proposal
 * kind id = 1 means amend proposal
 * kind id = 2 means bind propose processor
 * other is reserved */
contract CrossMultiSignDao is IDaoSetting, ReentrancyGuard, Initializable{
    using Counters       for Counters.Counter;
    using Timers         for Timers.Timestamp;
    using SafeCast       for uint256;
    using CrossDaoCommon for bytes;

    event ProposalCanceled(uint256 proposalId);

    struct ProposalCore {
        Timers.Timestamp voteEnd;
        bool             executed;
        bool             canceled;
        uint256          quorum;
        uint256          totalVotes;
    }

    struct Receipt {
        bool         hasVoted;
        uint8        support;
        uint96       votes;
    }

    struct ProposalDetails {
        uint8                       kindId;
        address                     proposer;
        uint256                     toChainID;
        bytes                       proposal;
        uint256                     forVotes;
        uint256                     againstVotes;
        uint256                     abstainVotes;
        mapping(address => Receipt) receipts;
        Signature[]                 signatures;
    }

    // proposal detail
    mapping(uint256 => ProposalDetails)  private _proposalDetails;
    // proposal vote info
    mapping(uint256 => ProposalCore)     private _proposals;
    // the smallest unused nonce of chain
    mapping(uint256 => Counters.Counter) private _nonces;
    // the term of voter
    Counters.Counter                     private currentTerm;
    IVotes                               private token;
    uint256                              private delay;
    uint256                              private currentProposalId;
    uint256                              private ratio;

    modifier onlyGovernance() {
        require(msg.sender == _executor(), "onlyGovernance");
        _;
    }

    function initialize(IVotes _tokenAddress, uint256 _votingDelay, uint256 _ratio) public initializer {
        require(_ratio <= 100 && _ratio > 0, "invalid ratio");
        require(_votingDelay != 0, "invalid vote delay");

        token = _tokenAddress;
        _nonces[block.chainid] = Counters.Counter(1);
        _nonces[type(uint256).max] = Counters.Counter(1);
        currentTerm = Counters.Counter(1);
        delay = _votingDelay;
        ratio = _ratio;
    }

    function changeVoters(
        address[] calldata _newVoters,
        uint256 _newTerm
    ) public override onlyGovernance {
        require(_newTerm - term() == 1, "dependent term is invalid");
        string memory errorMessage = "fail to change voter";
        (bool success, bytes memory returnData) = address(token).call(abi.encodeWithSignature("changeVoters(address[])", _newVoters));
        Address.verifyCallResult(success, returnData, errorMessage);
        currentTerm.increment();
    }

    function updateVotingRatio(
        uint256 _ratio,
        uint256 _newTerm
    ) public override onlyGovernance {
        require(_newTerm - term() == 1, "dependent term is invalid");
        if(_ratio <= 100 && _ratio > 0) {
            emit VotingRatioChanged(term(), _newTerm, ratio);
            ratio = _ratio;
        }
        currentTerm.increment();
    }

    function votingRatio() public view override returns(uint256) {
        return ratio;
    }

    function setVotingDelay(
        uint256 _votingDelay
    ) public override onlyGovernance {
        if (_votingDelay != 0) {
            emit VotingDelayChanged(delay, _votingDelay);
            delay = _votingDelay;
        }
    }

    function votingDelay() external view override returns(uint256) {
        return delay;
    }

    function bindNeighborChains(
        uint256[] calldata chainIDs
    ) public override onlyGovernance {
        for (uint256 i = 0; i < chainIDs.length; ++i) {
            if (_nonces[chainIDs[i]].current() == 0) {
                _nonces[chainIDs[i]] = Counters.Counter(1);
                emit NeighborChainBound(chainIDs[i]);
            }
        }
    }

    function propose(
        uint256            fromChainID,
        uint256            toChainID,
        uint8              kindId,
        uint256            voteTerm,
        uint256            nonce,
        bytes     calldata action,
        bytes32            descriptionHash
    ) external returns (uint256) {
        require(idle(), "cross multisign is busy");

        require(_getVotes(msg.sender) > 0, "proposer must be voter");
        _checkCrossHeader(fromChainID, toChainID);
        require(voteTerm == term(), "dependent term is invalid");
        
        if (kindId == 1) {
            require((toChainID != type(uint256).max) && (nonce < nonces(toChainID)), "nonce is not be used");
        } else {
            require(nonce == nonces(toChainID), "nonce is invalid");
        }

        if (kindId == 0) {
            require(toChainID == type(uint256).max, "only support broadcast");
        } else {
            require(toChainID != type(uint256).max, "only support unicast");
        }

        bytes memory proposalInfo = CrossDaoCommon.encodeCrossDaoTx(kindId, fromChainID, 
                        toChainID, voteTerm, nonce, action, descriptionHash);
        uint256 proposalID = uint256(keccak256(proposalInfo));

        ProposalDetails storage detail = _proposalDetails[proposalID];
        require(detail.proposer == address(0), "proposal id is existed");

        detail.proposer = msg.sender;
        detail.proposal = proposalInfo;
        detail.kindId = kindId;
        detail.toChainID = toChainID;
        _propose(proposalID);
        emit CrossDaoCommon.CrossDaoProposalCreated(proposalID, msg.sender, kindId, proposalInfo);
        return proposalID;
    }

    function cancel(uint256 proposalId) public {
        ProposalDetails storage details = _proposalDetails[proposalId];

        require(
            msg.sender == details.proposer || _getVotes(msg.sender) > 0,
            "proposer above threshold"
        );

        _cancel(proposalId);
    }

    function nonces(uint256 chainID) public view  returns (uint256) {
        return _nonces[chainID].current();
    }

    function term() public view returns (uint256) {
        return currentTerm.current();
    }

    function idle() public view returns (bool) {
        if (currentProposalId == 0) {
            return true;
        }

        ProposalState status = state(currentProposalId);
        if ((ProposalState.Defeated == status) || 
            (ProposalState.Executed == status) || 
            (ProposalState.Expired  == status) ||
            (ProposalState.Canceled == status)) {
            return true;
        }

        return false;
    }
    
    function proposalDeadline(
        uint256 proposalId
    ) public view virtual returns (uint256) {
        return _proposals[proposalId].voteEnd.getDeadline();
    }

    function castVoteBySig(
        uint256 proposalId,
        uint8   support,
        uint8   v,
        bytes32 r, 
        bytes32 s
    ) external returns (uint256) {
        return _castVote(proposalId, v, r, s, support);
    }

    function execute(
        uint256 proposalId
    ) external nonReentrant{
        ProposalState status = state(proposalId);
        require(status == ProposalState.Succeeded, "proposal not success");
        _proposals[proposalId].executed = true;

        ProposalDetails storage detail = _proposalDetails[proposalId];
        if (detail.kindId == 0) {
            CrossDaoTx memory dao = detail.proposal.decodeCrossDaoTx();
            bytes4 actionId = bytes4(Utils.bytesToBytes32(dao.action));
            if (actionId == IDaoSetting.changeVoters.selector ||
                actionId == IDaoSetting.updateVotingRatio.selector ||
                actionId == IDaoSetting.setVotingDelay.selector ||
                actionId == IDaoSetting.bindNeighborChains.selector) {
                string memory errorMessage = "fail to execute governor";
                (bool success, bytes memory returnData) = address(this).call(dao.action);
                Address.verifyCallResult(success, returnData, errorMessage);
            }
        }

        if (detail.kindId != 1) {
            _nonces[detail.toChainID].increment();
        }

        emit CrossDaoCommon.CrossDaoBridgeEvent(address(this), proposalId, detail.kindId, detail.proposal, _encodeSignatures(detail.signatures));
    }

    function state(uint256 proposalId) public view virtual returns (ProposalState) {
        ProposalCore storage proposal = _proposals[proposalId];

        if (proposal.executed) {
            return ProposalState.Executed;
        }

        if (proposal.canceled) {
            return ProposalState.Canceled;
        }

        uint256 deadline = proposalDeadline(proposalId);

        if (deadline == 0) {
            revert("unknown proposal id");
        }

        if (_quorumReached(proposalId)) {
            return ProposalState.Succeeded;
        }

        if (_quorumDefeated(proposalId)) {
            return ProposalState.Defeated;
        }

        if (deadline <= block.timestamp) {
            return ProposalState.Expired;
        }

        return ProposalState.Active;
    }

    function hasVoted(uint256 proposalId, address account) public view virtual returns (bool) {
        return _proposalDetails[proposalId].receipts[account].hasVoted;
    }

    function getReceipt(uint256 proposalId, address voter) public view virtual returns (Receipt memory) {
        return _proposalDetails[proposalId].receipts[voter];
    }

    function quorum(uint256 blockNumber) public view virtual returns (uint256) {
        return (token.getPastTotalSupply(blockNumber) * ratio + 99) / 100;
    }

    function _cancel(
        uint256 proposalId
    ) internal virtual returns (uint256) {
        ProposalState status = state(proposalId);

        require(
            status != ProposalState.Canceled && status != ProposalState.Expired && status != ProposalState.Executed,
            "proposal not active"
        );
        
        _proposals[proposalId].canceled = true;

        emit ProposalCanceled(proposalId);

        return proposalId;
    }

    function _setCurrentProposalID(uint256 proposalId) internal {
        currentProposalId = proposalId;
    }

    function _getVotes(address account) internal view returns (uint256) {
        return token.getPastVotes(account, block.number);
    }

    function _checkCrossHeader(
        uint256 fromChainID, 
        uint256 toChainID
    ) internal view {
        require(fromChainID == block.chainid, "from chainID must be my chainID");
        require(nonces(toChainID) != 0, "to chainID is not registered");
    }

    function _propose(
        uint256 proposalID
    ) internal virtual {
        ProposalCore storage proposal = _proposals[proposalID];
        require(proposal.voteEnd.isUnset(), "proposal already exists");

        _setCurrentProposalID(proposalID);
        uint64 deadline = block.timestamp.toUint64() + delay.toUint64();
        proposal.voteEnd.setDeadline(deadline);
        proposal.quorum = quorum(block.number);
        proposal.totalVotes = token.getPastTotalSupply(block.number);
    }

    function _executor() internal view virtual returns (address) {
        return address(this);
    }

    function _castVote(
        uint256 proposalId,
        uint8   v,
        bytes32 r, 
        bytes32 s,
        uint8   support
    ) internal virtual returns (uint256) {
        require(state(proposalId) == ProposalState.Active, "vote is not active");
        address account = ECDSA.recover(
            ECDSA.toEthSignedMessageHash(keccak256(abi.encode(address(this), proposalId, support))),
            v,
            r,
            s
        );
        require(account != address(0), "invalid signer");
        uint256 weight = _getVotes(account);
        require(weight != 0, "invalid voter");
        _countVote(proposalId, account, v, r, s, support, weight);
        emit CrossDaoCommon.CrossDaoVoteCast(account, proposalId, support, weight);

        return weight;
    }

    function _countVote(
        uint256 proposalId,
        address account,
        uint8   v,
        bytes32 r, 
        bytes32 s,
        uint8   support,
        uint256 weight
    ) internal virtual {
        ProposalDetails storage details = _proposalDetails[proposalId];
        Receipt storage receipt = details.receipts[account];

        require(!receipt.hasVoted, "vote already cast");
        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = SafeCast.toUint96(weight);

        if (support == uint8(VoteType.Against)) {
            details.againstVotes += weight;
        } else if (support == uint8(VoteType.For)) {
            details.forVotes += weight;
            details.signatures.push(Signature(r, s, v));
        } else if (support == uint8(VoteType.Abstain)) {
            details.abstainVotes += weight;
        } else {
            revert("invalid vote type");
        }
    }

    function _quorumReached(uint256 proposalId) internal view virtual returns (bool) {
        ProposalDetails storage details = _proposalDetails[proposalId];
        ProposalCore storage proposal = _proposals[proposalId];
        return proposal.quorum <= details.forVotes;
    }

    function _quorumDefeated(uint256 proposalId) internal view virtual returns (bool) {
        ProposalDetails storage details = _proposalDetails[proposalId];
        ProposalCore storage proposal = _proposals[proposalId];
        return ((details.againstVotes + details.abstainVotes + proposal.quorum) > proposal.totalVotes);
    }

    function _encodeSignatures(Signature[] memory signs) internal view virtual returns (bytes[] memory _bytesSigns) {
        _bytesSigns = new bytes[](signs.length);
        for (uint256 i = 0; i < signs.length; ++i) {
            _bytesSigns[i] = abi.encodePacked(signs[i].r, signs[i].s, signs[i].v);
        }
    }
}