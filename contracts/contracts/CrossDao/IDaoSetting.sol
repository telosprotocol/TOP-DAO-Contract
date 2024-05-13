// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IDaoSetting {
    event VotingRatioChanged(
        uint256 newTerm,
        uint256 electionTerm,
        uint256 newRatio
    );

    event VotingDelayChanged(
        uint256 oldDelay,
        uint256 newDelay
    );

    event NeighborChainBound(
        uint256 chainID
    );

    event VoterChanged(
        uint256 termID,
        address voter
    );

    function changeVoters(address[] calldata _newVoters, uint256 _newTerm) external;
    
    function updateVotingRatio(uint256 _ratio, uint256 _newTerm) external;
    function votingRatio() external view returns(uint256);
    
    function setVotingDelay(uint256 _votingDelay) external;
    function votingDelay() external view returns(uint256);
    
    function bindNeighborChains(uint256[] calldata chainIDs) external;  
}