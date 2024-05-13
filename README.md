## DAO Smart Contract Overview

The DAO smart contract enables democratic control over the functionality of other contracts through a well-designed voting system, allowing for proposal deliberation and execution via democratic voting. The voting logic is decoupled from the DAO contract itself to accommodate diverse factors influencing voting weight, such as staking economy, personal credibility, domain knowledge, and democratic procedures. Therefore, the DAO is divided into two components: Vote Management and Proposal Governance, with a unified ABI interface provided for proposal governance.

### Vote Management

This component manages accounts with voting rights and their corresponding votes, where the design of voting weight affects the influence of voting users. Typically, vote management treats votes as ERC20-like assets, allowing dynamic actions like minting, burning, transferring, and delegation. In the initial stage, a more conservative and secure static approach is adopted:
1) Voters are determined at contract deployment or initialization and remain immutable.
2) Each voter's vote count is determined at contract deployment or initialization and remains consistent and immutable.

### Proposal Governance

Proposal governance consists of four stages: proposal initiation, voter verification, voting, and execution of approved proposals. Each stage corresponds to Proposal, Review, Voting, and Execution stages, respectively. Using Proposal A as an example, the typical proposal governance process is outlined as follows:
1) Proposer initiates Proposal A, and the governance contract saves the proposal and emits a proposal event.
2) Voters monitor the proposal event and review Proposal A.
3) Upon successful review, voters cast their votes in support of Proposal A.
4) The executor tallies the votes, and if the vote count exceeds the predetermined approval threshold, Proposal A is executed.

The measurement method for each stage of proposal governance uses block height differences, such as the block time for the voting period (requiring irreversible time). All proposals under management use the same voters and approval conditions without differentiation. The actual review period may span both the review and voting periods.

Proposal governance includes the following capabilities:
1) Proposal initiation and cancellation: Proposers need a certain number of votes (not required during initialization) to initiate proposals; only the proposer can cancel a proposal, and only if it has not been executed, with cancellation allowed only once.
2) Voting: Each proposal can be voted on at most once during the voting period, with voting only permitted during the voting period; voters can vote in favor, against, or abstain.
3) Execution: Anyone can execute a proposal, but only if the vote count exceeds the predetermined approval threshold and only once; proposals failing to meet the threshold are considered failed and cannot be executed. When tallying votes, only votes cast before the end of the voting period are counted. Execution must occur after the voting period.

### Security

Security-related content is interwoven throughout the descriptions above and will not be reiterated.

### Upgrades

Upgrades are conducted via pausing the old contract, deploying the new contract, and importing data. For governance contracts, no data import is required, and the new contract does not process unresolved proposals from the old contract. To handle old proposals, users must resubmit them to the new contract.

### Fees

The proposal governance contract does not charge fees for any operations.