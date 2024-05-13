// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/governance/utils/IVotes.sol";

contract ScalableVotes is IVotes {
    event VoterAdded(
        address voter
    );
    
    event VoterDeleted(
        address voter
    );
    
    struct Checkpoint {
        uint256 fromBlock;
        uint256 votes;
    }

    address[] private voters;
    mapping(address => uint256) private checkpoints;
    Checkpoint private totalSupplyCheckpoint;
    address private governor;

    modifier onlyGovernance() {
        require(msg.sender == governor, "Governor: onlyGovernance");
        _;
    }

    constructor(address[] memory _voters, address _governor) payable {
        require(_voters.length >= 3, "number of voters must more than 3");
        require(_governor != address(0), "invalid governor");
        for (uint256 i = 0; i < _voters.length; ++i) {
            require(_voters[i] != address(0), "invalid voter");
            require(checkpoints[_voters[i]] == 0, "voter can not be repeated");
            checkpoints[_voters[i]] = block.number;
            voters.push(_voters[i]);
        }

        totalSupplyCheckpoint = Checkpoint(block.number, _voters.length);
        governor = _governor;
    }

    function getVotes(address account) override external view returns (uint256) {
        if (checkpoints[account] != 0) {
            return 1;
        }

        return 0;
    }

    function getPastVotes(address account, uint256 blockNumber) override external view returns (uint256) {
        require(blockNumber <= block.number, "block not yet mined");
        require(checkpoints[account] <= blockNumber, "no vote"); 
        if (checkpoints[account] != 0) {
            return 1;
        }

        return 0;
    }

    function getPastTotalSupply(uint256 blockNumber) override external view returns (uint256) {
        require(blockNumber <= block.number, "block not yet mined");
        return totalSupplyCheckpoint.votes;
    }

    function changeVoters(address[] calldata _voters) external onlyGovernance {
        address tempVoter;
        for (uint256 i = 0; i < voters.length; ) {
            tempVoter = voters[i];
            if (!_exist(tempVoter, _voters)) {
                voters[i] = voters[voters.length - 1];
                voters.pop();
                delete checkpoints[tempVoter];
                totalSupplyCheckpoint.votes--;
                emit VoterDeleted(tempVoter);
            } else {
                ++i;
            }
        }

        for (uint256 i = 0; i < _voters.length; ++i) {
            if ((checkpoints[_voters[i]] == 0) && (_voters[i] != address(0))) {
                voters.push(_voters[i]);
                checkpoints[_voters[i]] = block.number;
                totalSupplyCheckpoint.votes++;
                emit VoterAdded(_voters[i]);
            }
        }
    }

    function _exist(address _voter, address[] calldata _voters) internal pure returns(bool) {
        for (uint256 i = 0; i < _voters.length; ++i) {
            if (_voter == _voters[i]) {
                return true;
            }
        }

        return false;
    }

    function delegates(address /*account*/) override external pure returns (address delegated) {
        (delegated);
        require(false, "not support");
    }

    function delegate(address /*delegatee*/) override external pure{
        require(false, "not support");
    }

    function delegateBySig(
        address /*delegatee*/,
        uint256 /*nonce*/,
        uint256 /*expiry*/,
        uint8 /*v*/,
        bytes32 /*r*/,
        bytes32 /*s*/
    ) override external pure {
        require(false, "not support");
    }
}