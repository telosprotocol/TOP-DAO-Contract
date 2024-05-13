// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./ICrossGovernance.sol";
import "./IDaoSetting.sol";

contract DaoExecutor is IDaoSetting, ICrossGovernance, Initializable{
    using ECDSA      for bytes32;
    using Counters   for Counters.Counter;

    struct RatioTerm {
        uint256      ratio;
        uint256      term;
    }

    mapping(uint256 => Counters.Counter) private _nonces;
    mapping(uint256 => mapping(address => bool)) private terms;
    mapping(uint256 => RatioTerm) private ratios;
    mapping(uint256 => address) private proposalProcessors;
    uint256 public  peerChainID;
    address public  peerDao;
    uint256 public  term;
    uint256 private numOfVoters;
    address public  admin;

    event NonceChanged(
        uint256 chainID,
        uint256 termID,
        uint256 nonce
    );

    event TermChanged(
        uint256 termID
    );

    modifier onlyGovernance() {
        require(msg.sender == _executor(), "onlyGovernance");
        _;
    }
    
    function initialize(address[] calldata _voters, uint256 _peerChainID, address _peerDao, uint256 _ratio, address _admin) external initializer {
        require(_ratio <= 100 && _ratio > 0, "invalid ratio");
        require(_admin != address(0), "invalid admin");
        _changeVoters(_voters, 1);
        _changeRatio(_ratio, 1, 1);

        require(_peerDao != address(0), "invalid dao address");
        peerDao     = _peerDao;
        peerChainID = _peerChainID;

        _nonces[block.chainid] = Counters.Counter(1);
        _nonces[type(uint256).max] = Counters.Counter(1);

        admin = _admin;
    }

    function isVoterExist(uint256 _term, address voter) public view override returns (bool) {
        return terms[ratios[_term].term][voter];
    }

    function nonces(uint256 chainID) public view  returns (uint256) {
        return _nonces[chainID].current();
    }
    
    function _executor() internal view override returns (address) {
        return address(this);
    }

    function _isAdmin() internal view override returns (bool) {
        if (msg.sender == admin) {
            return true;
        }

        return false;
    }

    function _checkCrossDaoHeader(uint256 fromChainID, uint256 toChainID, address fromAddress) internal view override {
        require(fromChainID == peerChainID, "invalid from chain id");
        require(toChainID == block.chainid || toChainID == type(uint256).max, "invalid to chain id");
        require(fromAddress == peerDao, "invalid peer dao");
    }

    function _changeNonce(uint256 chainID, uint256 newNonce, uint256 currentTerm) internal override {
        require(currentTerm == term, "invalid term");
        require(newNonce == nonces(chainID), "invalid nonce");
        _nonces[chainID].increment();
        emit NonceChanged(chainID, currentTerm, newNonce);
    }

    function _changeTerm(uint256 newTerm) internal override{
        require(newTerm - term == 1, "invalid new term");
        term = newTerm;
        emit TermChanged(newTerm);
    }

    function _quorum(uint256 _term) internal view override returns (uint256) {
        return (numOfVoters * ratios[_term].ratio + 99) / 100;
    }

    function changeVoters(address[] memory _voters, uint256 newTerm) public override onlyGovernance {
        _changeVoters(_voters, newTerm);
        _changeRatio(ratios[newTerm - 1].ratio, newTerm, newTerm);
    }

    function _changeVoters(address[] memory _voters, uint256 newTerm) internal {
        mapping(address => bool) storage termVoters = terms[newTerm];
        _changeTerm(newTerm);
        numOfVoters = 0;
        for (uint256 i = 0; i < _voters.length; ++i) {
            if ((_voters[i] != address(0)) && (!termVoters[_voters[i]])) {
                termVoters[_voters[i]] = true;
                numOfVoters++;
            }
            emit VoterChanged(newTerm, _voters[i]);
        }
    }

    function updateVotingRatio(
        uint256 _ratio,
        uint256 _newTerm
    ) public override onlyGovernance {
        _changeTerm(_newTerm);
        _changeRatio(_ratio, _newTerm, ratios[_newTerm - 1].term);
    }

    function votingRatio() public view override returns(uint256) {
        return ratios[term].ratio;
    }

    function setVotingDelay(
        uint256 /*_votingDelay*/
    ) public override onlyGovernance {
    }

    function votingDelay() external view override returns(uint256) {
    }

    function bindNeighborChains(
        uint256[] calldata /*chainIDs*/
    ) public override onlyGovernance {

    }

    function bindProposalProcessor(
        uint256 kindId, 
        address token
    ) public override onlyGovernance {
        require(kindId > 2, "invalid kind id");
        if ((proposalProcessors[kindId] == address(0)) && (token.code.length > 0)) {
            proposalProcessors[kindId] = token;
        }
    }

    function proposalProcessor(uint256 kindId) public view override returns(address) {
        return proposalProcessors[kindId];
    }

    function _changeRatio(
        uint256 _ratio,
        uint256 _newTerm,
        uint256 _electionTerm
    ) internal {
        if(_ratio <= 100 && _ratio > 0) {
            ratios[_newTerm] = RatioTerm(_ratio, _electionTerm);
            emit VotingRatioChanged(_newTerm, _electionTerm, _ratio);
        }
    }
}