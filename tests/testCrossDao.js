const chai = require("chai");
const expect = chai.expect;
const Web3 = require('web3');

var utils = require('ethers').utils;
const { AddressZero,MaxUint256} = require("ethers").constants
const { BigNumber } = require('ethers')

const BN = require('bn.js');
chai.use(require('chai-bn')(BN));
const borsh = require("borsh")

const hre = require("hardhat");
const { ethers, upgrades } = require("hardhat");
const buffer = require('safe-buffer').Buffer;

const toWei = (val) => ethers.utils.parseEther('' + val)
const {rlp,bufArrToArr} = require('ethereumjs-util')
const { keccak256 } = require('@ethersproject/keccak256')
const Web3EthAbi = require('web3-eth-abi')

describe("CrossDao", function () {
    beforeEach(async function () {
        //准备必要账户
        [deployer, admin, miner, user, user1, ,user2, user3, redeem] = await hre.ethers.getSigners()
        owner = deployer
        console.log("deployer account:", deployer.address)
        console.log("owner account:", owner.address)
        console.log("admin account:", admin.address)
        console.log("team account:", miner.address)
        console.log("user account:", user.address)
        console.log("user1 account:", user1.address)
        console.log("user2 account:", user2.address)
        console.log("user3 account:", user3.address)
        console.log("redeem account:", redeem.address)

        daoExecutorCon = await ethers.getContractFactory("DaoExecutor", deployer)
        daoExecutor = await daoExecutorCon.deploy()
        await daoExecutor.deployed()
        console.log("+++++++++++++daoExecutor+++++++++++++++ ", daoExecutor.address)

        crossMultiSignDaoCon = await ethers.getContractFactory("CrossMultiSignDao", deployer)
        crossMultiSignDao = await crossMultiSignDaoCon.deploy()
        await crossMultiSignDao.deployed()
        
        console.log("+++++++++++++CrossMultiSignDao+++++++++++++++ ", crossMultiSignDao.address)
        scalableVotesCon = await ethers.getContractFactory("ScalableVotes", deployer)
        scalableVotes = await scalableVotesCon.deploy([user1.address, user2.address, user3.address], crossMultiSignDao.address)
        await scalableVotes.deployed()
        console.log("+++++++++++++scalableVotes+++++++++++++++ ", scalableVotes.address)

        await expect(crossMultiSignDao.initialize(scalableVotes.address, 7, 120)).to.be.revertedWith('invalid ratio')
        await expect(crossMultiSignDao.initialize(scalableVotes.address, 0, 50)).to.be.revertedWith('invalid vote delay')
        await crossMultiSignDao.initialize(scalableVotes.address, 7, 50)
        await expect(daoExecutor.initialize([user1.address, user2.address, user3.address], 31337, crossMultiSignDao.address, 0, admin.address)).to.be.revertedWith("invalid ratio")
        await expect(daoExecutor.initialize([user1.address, user2.address, user3.address], 31337, crossMultiSignDao.address, 1, AddressZero)).to.be.revertedWith("invalid admin")
        await expect(daoExecutor.initialize([user1.address, user2.address, user3.address], 31337, AddressZero, 1, admin.address)).to.be.revertedWith("invalid dao address")
        await daoExecutor.initialize([user1.address, user2.address, user3.address], 31337, crossMultiSignDao.address, 50, admin.address)

        erc20SampleCon = await ethers.getContractFactory("ERC20TokenSample", user)
        erc20Sample = await erc20SampleCon.deploy()
        await erc20Sample.deployed()
    })

    it('CrossDao', async () => {
        let transferCalldata = crossMultiSignDao.interface.encodeFunctionData('setVotingDelay', [6])
        await expect(crossMultiSignDao.propose(1, 1, 0, 1, 1, transferCalldata, keccak256(Array.from(1)))).to.be.revertedWith("proposer must be voter")
        await expect(crossMultiSignDao.connect(user1).propose(1, 1, 0, 1, 1, transferCalldata, keccak256(transferCalldata))).to.be.revertedWith('from chainID must be my chainID')
        await expect(crossMultiSignDao.connect(user1).propose(31337, 31337, 0, 1, 1, transferCalldata, keccak256(transferCalldata))).to.be.revertedWith('only support broadcast')
        let tx = await crossMultiSignDao.connect(user1).callStatic["propose(uint256,uint256,uint8,uint256,uint256,bytes,bytes32)"](31337, MaxUint256, 0, 1, 1, transferCalldata, keccak256(transferCalldata))
        await crossMultiSignDao.connect(user1).propose(31337, MaxUint256, 0, 1, 1, transferCalldata, keccak256(transferCalldata))
        hash32 = keccak256(Web3EthAbi.encodeParameters(['address', 'uint256', 'uint8'], [crossMultiSignDao.address, tx, 1]))
        let signature = await user1.signMessage(ethers.utils.arrayify(hash32))
        await crossMultiSignDao.connect(user1).castVoteBySig(tx, 1, "0x"+ signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))
        await expect(crossMultiSignDao.execute(tx)).to.be.revertedWith('proposal not success')
        await expect(crossMultiSignDao.connect(user1).castVoteBySig(tx, 1, "0x"+ signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))).to.be.revertedWith('vote already cast')
        signature = await user2.signMessage(ethers.utils.arrayify(hash32))
        await crossMultiSignDao.connect(user2).castVoteBySig(tx, 1, "0x"+ signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))
        tx = await crossMultiSignDao.execute(tx)
        rc = await tx.wait()
        calldata = await Web3EthAbi.encodeParameters(['address', 'bytes32[]', 'bytes'], [rc.events[1].address, rc.events[1].topics, rc.events[1].data])
        await daoExecutor.connect(admin).execute(calldata)

        //==========
        transferCalldata = daoExecutor.interface.encodeFunctionData('bindProposalProcessor', [3, erc20Sample.address])
        //let tx = await crossMultiSignDao.connect(user1).callStatic["propose(uint256,uint256,uint8,uint256,uint256,bytes,bytes32)"](31337, MaxUint256, 0, 1, 1, transferCalldata, keccak256(transferCalldata))
        tx = await crossMultiSignDao.connect(user1).callStatic["propose(uint256,uint256,uint8,uint256,uint256,bytes,bytes32)"](31337, 31337, 2, 1, 1, transferCalldata, keccak256(Array.from(1)))
        await crossMultiSignDao.connect(user1).propose(31337, 31337, 2, 1, 1, transferCalldata, keccak256(Array.from(1)))
        hash32 = keccak256(Web3EthAbi.encodeParameters(['address', 'uint256', 'uint8'], [crossMultiSignDao.address, tx, 1]))
        signature = await user1.signMessage(ethers.utils.arrayify(hash32))
        await crossMultiSignDao.connect(user1).castVoteBySig(tx, 1, "0x"+ signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))

        signature = await user2.signMessage(ethers.utils.arrayify(hash32))
        await crossMultiSignDao.connect(user2).castVoteBySig(tx, 1, "0x"+ signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))
        tx = await crossMultiSignDao.execute(tx)
        rc = await tx.wait()
        calldata = await Web3EthAbi.encodeParameters(['address', 'bytes32[]', 'bytes'], [rc.events[0].address, rc.events[0].topics, rc.events[0].data])
        await daoExecutor.connect(admin).execute(calldata)

        await erc20Sample.transfer(daoExecutor.address, 10000000000)
        transferCalldata = erc20Sample.interface.encodeFunctionData('transfer', [admin.address, 1000])
        tx = await crossMultiSignDao.connect(user1).callStatic["propose(uint256,uint256,uint8,uint256,uint256,bytes,bytes32)"](31337, 31337, 3, 1, 2, transferCalldata, keccak256(Array.from(1)))
        await crossMultiSignDao.connect(user1).propose(31337, 31337, 3, 1, 2, transferCalldata, keccak256(Array.from(1)))
        hash32 = keccak256(Web3EthAbi.encodeParameters(['address', 'uint256', 'uint8'], [crossMultiSignDao.address, tx, 1]))
        signature = await user1.signMessage(ethers.utils.arrayify(hash32))
        await crossMultiSignDao.connect(user1).castVoteBySig(tx, 1, "0x"+ signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))
        
        signature = await redeem.signMessage(ethers.utils.arrayify(hash32))
        await expect(crossMultiSignDao.connect(redeem).castVoteBySig(tx, 1, "0x"+ signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))).to.be.revertedWith('invalid voter')
        signature = await user2.signMessage(ethers.utils.arrayify(hash32))
        await crossMultiSignDao.connect(user2).castVoteBySig(tx, 1, "0x"+ signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))
 
        tx = await crossMultiSignDao.execute(tx)
        rc = await tx.wait()
        calldata = await Web3EthAbi.encodeParameters(['address', 'bytes32[]', 'bytes'], [rc.events[0].address, rc.events[0].topics, rc.events[0].data])
        await daoExecutor.connect(admin).execute(calldata)
        expect(await erc20Sample.balanceOf(admin.address)).to.be.equal(1000)

        //change voter
        transferCalldata = crossMultiSignDao.interface.encodeFunctionData('changeVoters', [[admin.address, miner.address, redeem.address], 1])
        await expect(crossMultiSignDao.connect(user1).propose(31337, 31337, 0, 0, 2, transferCalldata, keccak256(transferCalldata))).to.be.revertedWith('dependent term is invalid')
        await expect(crossMultiSignDao.connect(user1).propose(31337, 31337, 0, 1, 2, transferCalldata, keccak256(transferCalldata))).to.be.revertedWith('nonce is invalid')
        await expect(crossMultiSignDao.connect(user1).propose(31337, 31337, 0, 1, 3, transferCalldata, keccak256(transferCalldata))).to.be.revertedWith('only support broadcast')
        
        tx = await crossMultiSignDao.connect(user1).callStatic["propose(uint256,uint256,uint8,uint256,uint256,bytes,bytes32)"](31337, MaxUint256, 0, 1, 2, transferCalldata, keccak256(transferCalldata))
        await crossMultiSignDao.connect(user1).propose(31337, MaxUint256, 0, 1, 2, transferCalldata, keccak256(transferCalldata))
        await expect(crossMultiSignDao.connect(user1).propose(31337, MaxUint256, 0, 1, 2, transferCalldata, keccak256(transferCalldata))).to.be.revertedWith('cross multisign is busy')
        hash32 = keccak256(Web3EthAbi.encodeParameters(['address', 'uint256', 'uint8'], [crossMultiSignDao.address, tx, 1]))
        signature = await user1.signMessage(ethers.utils.arrayify(hash32))
        await crossMultiSignDao.connect(user1).castVoteBySig(tx, 1, "0x"+ signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))
        signature = await user2.signMessage(ethers.utils.arrayify(hash32))
        await crossMultiSignDao.connect(user2).castVoteBySig(tx, 1, "0x"+ signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))
 
        await expect(crossMultiSignDao.execute(tx)).to.be.revertedWith('dependent term is invalid')
        await expect(crossMultiSignDao.connect(redeem).cancel(tx)).to.be.revertedWith('proposer above threshold')
        await crossMultiSignDao.connect(user2).cancel(tx)

        transferCalldata = crossMultiSignDao.interface.encodeFunctionData('changeVoters', [[admin.address, miner.address, redeem.address], 2])
        tx = await crossMultiSignDao.connect(user1).callStatic["propose(uint256,uint256,uint8,uint256,uint256,bytes,bytes32)"](31337, MaxUint256, 0, 1, 2, transferCalldata, keccak256(transferCalldata))
        await crossMultiSignDao.connect(user1).propose(31337, MaxUint256, 0, 1, 2, transferCalldata, keccak256(transferCalldata))
        hash32 = keccak256(Web3EthAbi.encodeParameters(['address', 'uint256', 'uint8'], [crossMultiSignDao.address, tx, 1]))
        signature = await user1.signMessage(ethers.utils.arrayify(hash32))
        await crossMultiSignDao.connect(user1).castVoteBySig(tx, 1, "0x"+ signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))
        signature = await user2.signMessage(ethers.utils.arrayify(hash32))
        await crossMultiSignDao.connect(user2).castVoteBySig(tx, 1, "0x"+ signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))
        tx = await crossMultiSignDao.execute(tx)

        rc = await tx.wait()
        let calldata1 = await Web3EthAbi.encodeParameters(['address', 'bytes32[]', 'bytes'], [rc.events[rc.events.length - 1].address, rc.events[rc.events.length - 1].topics, rc.events[rc.events.length - 1].data])
        // await daoExecutor.connect(admin).execute(calldata1)

        //transfer
        transferCalldata = erc20Sample.interface.encodeFunctionData('transfer', [admin.address, 1000])
        tx = await crossMultiSignDao.connect(admin).callStatic["propose(uint256,uint256,uint8,uint256,uint256,bytes,bytes32)"](31337, 31337, 3, 2, 3, transferCalldata, keccak256(transferCalldata))
        await expect(crossMultiSignDao.connect(admin).propose(31337, MaxUint256, 3, 2, 3, transferCalldata, keccak256(transferCalldata))).to.be.revertedWith('only support unicast')
        await crossMultiSignDao.connect(admin).propose(31337, 31337, 3, 2, 3, transferCalldata, keccak256(transferCalldata))
        
        hash32 = keccak256(Web3EthAbi.encodeParameters(['address', 'uint256', 'uint8'], [crossMultiSignDao.address, tx, 4]))
        signature = await admin.signMessage(ethers.utils.arrayify(hash32))
        await expect(crossMultiSignDao.connect(redeem).castVoteBySig(tx, 4, "0x"+ signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))).to.be.revertedWith('invalid vote type')
        signature = await user1.signMessage(ethers.utils.arrayify(hash32))
        await expect(crossMultiSignDao.connect(redeem).castVoteBySig(tx, 4, "0x"+ signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))).to.be.revertedWith('invalid voter')
        
        hash32 = keccak256(Web3EthAbi.encodeParameters(['address', 'uint256', 'uint8'], [crossMultiSignDao.address, tx, 1]))
        signature = await admin.signMessage(ethers.utils.arrayify(hash32))
        await crossMultiSignDao.connect(admin).castVoteBySig(tx, 1, "0x"+ signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))
        await expect(crossMultiSignDao.execute(tx)).to.be.revertedWith('proposal not success')
        signature = await miner.signMessage(ethers.utils.arrayify(hash32))
        await crossMultiSignDao.connect(miner).castVoteBySig(tx, 1, "0x"+ signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))
        
        tx = await crossMultiSignDao.execute(tx)
        rc = await tx.wait()
        calldata = await Web3EthAbi.encodeParameters(['address', 'bytes32[]', 'bytes'], [rc.events[rc.events.length - 1].address, rc.events[rc.events.length - 1].topics, rc.events[rc.events.length - 1].data])
        await expect(daoExecutor.connect(admin).execute(calldata)).to.be.revertedWith('invalid voter')
        await daoExecutor.connect(admin).execute(calldata1)
        await daoExecutor.connect(admin).execute(calldata)

        transferCalldata = erc20Sample.interface.encodeFunctionData('transferFrom', [redeem.address, admin.address, 1000])
        tx = await crossMultiSignDao.connect(admin).callStatic["propose(uint256,uint256,uint8,uint256,uint256,bytes,bytes32)"](31337, 31337, 3, 2, 4, transferCalldata, keccak256(transferCalldata))
        await crossMultiSignDao.connect(admin).propose(31337, 31337, 3, 2, 4, transferCalldata, keccak256(transferCalldata))
                
        hash32 = keccak256(Web3EthAbi.encodeParameters(['address', 'uint256', 'uint8'], [crossMultiSignDao.address, tx, 1]))
        signature = await admin.signMessage(ethers.utils.arrayify(hash32))
        await crossMultiSignDao.connect(admin).castVoteBySig(tx, 1, "0x"+ signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))
        signature = await miner.signMessage(ethers.utils.arrayify(hash32))
        await crossMultiSignDao.connect(miner).castVoteBySig(tx, 1, "0x"+ signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))
        tx = await crossMultiSignDao.execute(tx)
        rc = await tx.wait()
        calldata = await Web3EthAbi.encodeParameters(['address', 'bytes32[]', 'bytes'], [rc.events[rc.events.length - 1].address, rc.events[rc.events.length - 1].topics, rc.events[rc.events.length - 1].data])
        await expect(daoExecutor.connect(admin).execute(calldata)).to.be.revertedWith('ERC20: insufficient allowance')

        transferCalldata = erc20Sample.interface.encodeFunctionData('transferFrom', [redeem.address, admin.address, 1000])
        tx = await crossMultiSignDao.connect(admin).callStatic["propose(uint256,uint256,uint8,uint256,uint256,bytes,bytes32)"](31337, 31337, 1, 2, 4, transferCalldata, keccak256(transferCalldata))
        await crossMultiSignDao.connect(admin).propose(31337, 31337, 1, 2, 4, transferCalldata, keccak256(transferCalldata))

        hash32 = keccak256(Web3EthAbi.encodeParameters(['address', 'uint256', 'uint8'], [crossMultiSignDao.address, tx, 1]))
        signature = await admin.signMessage(ethers.utils.arrayify(hash32))
        await crossMultiSignDao.connect(admin).castVoteBySig(tx, 1, "0x"+ signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))
        signature = await miner.signMessage(ethers.utils.arrayify(hash32))
        await crossMultiSignDao.connect(miner).castVoteBySig(tx, 1, "0x"+ signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))
        tx = await crossMultiSignDao.execute(tx)
        rc = await tx.wait()
        calldata = await Web3EthAbi.encodeParameters(['address', 'bytes32[]', 'bytes'], [rc.events[rc.events.length - 1].address, rc.events[rc.events.length - 1].topics, rc.events[rc.events.length - 1].data])
        await daoExecutor.connect(admin).execute(calldata)

        transferCalldata = erc20Sample.interface.encodeFunctionData('transfer', [redeem.address, 1000])
        tx = await crossMultiSignDao.connect(admin).callStatic["propose(uint256,uint256,uint8,uint256,uint256,bytes,bytes32)"](31337, 31337, 3, 2, 5, transferCalldata, keccak256(transferCalldata))
        await crossMultiSignDao.connect(admin).propose(31337, 31337, 3, 2, 5, transferCalldata, keccak256(transferCalldata))
                
        hash32 = keccak256(Web3EthAbi.encodeParameters(['address', 'uint256', 'uint8'], [crossMultiSignDao.address, tx, 1]))
        signature = await admin.signMessage(ethers.utils.arrayify(hash32))
        await crossMultiSignDao.connect(admin).castVoteBySig(tx, 1, "0x"+ signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))
        signature = await miner.signMessage(ethers.utils.arrayify(hash32))
        await crossMultiSignDao.connect(miner).castVoteBySig(tx, 1, "0x"+ signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))
        tx = await crossMultiSignDao.execute(tx)
        rc = await tx.wait()
        calldata = await Web3EthAbi.encodeParameters(['address', 'bytes32[]', 'bytes'], [rc.events[rc.events.length - 1].address, rc.events[rc.events.length - 1].topics, rc.events[rc.events.length - 1].data])
        await daoExecutor.connect(admin).execute(calldata)

        transferCalldata = crossMultiSignDao.interface.encodeFunctionData('updateVotingRatio', [60, 3])
        tx = await crossMultiSignDao.connect(admin).callStatic["propose(uint256,uint256,uint8,uint256,uint256,bytes,bytes32)"](31337, MaxUint256, 0, 2, 3, transferCalldata, keccak256(transferCalldata))
        await crossMultiSignDao.connect(admin).propose(31337, MaxUint256, 0, 2, 3, transferCalldata, keccak256(transferCalldata))
        hash32 = keccak256(Web3EthAbi.encodeParameters(['address', 'uint256', 'uint8'], [crossMultiSignDao.address, tx, 1]))
        signature = await admin.signMessage(ethers.utils.arrayify(hash32))
        await crossMultiSignDao.connect(admin).castVoteBySig(tx, 1, "0x"+ signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))
        signature = await miner.signMessage(ethers.utils.arrayify(hash32))
        await crossMultiSignDao.connect(miner).castVoteBySig(tx, 1, "0x"+ signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))
        tx = await crossMultiSignDao.execute(tx)
        rc = await tx.wait()
        calldata = await Web3EthAbi.encodeParameters(['address', 'bytes32[]', 'bytes'], [rc.events[rc.events.length - 1].address, rc.events[rc.events.length - 1].topics, rc.events[rc.events.length - 1].data])
        await daoExecutor.connect(admin).execute(calldata)

        transferCalldata = crossMultiSignDao.interface.encodeFunctionData('bindNeighborChains', [[1,2,3]])
        tx = await crossMultiSignDao.connect(admin).callStatic["propose(uint256,uint256,uint8,uint256,uint256,bytes,bytes32)"](31337, MaxUint256, 0, 3, 4, transferCalldata, keccak256(transferCalldata))
        await crossMultiSignDao.connect(admin).propose(31337, MaxUint256, 0, 3, 4, transferCalldata, keccak256(transferCalldata))
        hash32 = keccak256(Web3EthAbi.encodeParameters(['address', 'uint256', 'uint8'], [crossMultiSignDao.address, tx, 1]))
        signature = await admin.signMessage(ethers.utils.arrayify(hash32))
        await crossMultiSignDao.connect(admin).castVoteBySig(tx, 1, "0x"+ signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))
        signature = await miner.signMessage(ethers.utils.arrayify(hash32))
        await crossMultiSignDao.connect(miner).castVoteBySig(tx, 1, "0x"+ signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))
        tx = await crossMultiSignDao.execute(tx)
        rc = await tx.wait()
        calldata = await Web3EthAbi.encodeParameters(['address', 'bytes32[]', 'bytes'], [rc.events[rc.events.length - 1].address, rc.events[rc.events.length - 1].topics, rc.events[rc.events.length - 1].data])
        await daoExecutor.connect(admin).execute(calldata)
    })

    it('DaoExecutor', async () => {
        let transferCalldata = crossMultiSignDao.interface.encodeFunctionData('setVotingDelay', [3])
        let tx = await crossMultiSignDao.connect(user1).callStatic["propose(uint256,uint256,uint8,uint256,uint256,bytes,bytes32)"](31337, MaxUint256, 0, 1, 1, transferCalldata, keccak256(transferCalldata))
        await crossMultiSignDao.connect(user1).propose(31337, MaxUint256, 0, 1, 1, transferCalldata, keccak256(transferCalldata))
        hash32 = keccak256(Web3EthAbi.encodeParameters(['address', 'uint256', 'uint8'], [crossMultiSignDao.address, tx, 1]))
        let signature = await user1.signMessage(ethers.utils.arrayify(hash32))
        await crossMultiSignDao.connect(user1).castVoteBySig(tx, 1, "0x" + signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))
        signature = await user2.signMessage(ethers.utils.arrayify(hash32))
        await crossMultiSignDao.connect(user2).castVoteBySig(tx, 1, "0x" + signature.toString(16).substr(130,2), "0x" + signature.toString(16).substr(2,64), "0x" + signature.toString(16).substr(66,64))
        tx = await crossMultiSignDao.execute(tx)
        rc = await tx.wait()

        let calldata = await Web3EthAbi.encodeParameters(['address', 'bytes32[]', 'bytes'], [rc.events[0].address, rc.events[0].topics, rc.events[0].data])
        await expect(daoExecutor.connect(admin).execute(calldata)).to.be.revertedWith('invalid topic')
        calldata = await Web3EthAbi.encodeParameters(['address', 'bytes32[]', 'bytes'], [admin.address, rc.events[1].topics, rc.events[1].data])
        await expect(daoExecutor.connect(admin).execute(calldata)).to.be.revertedWith('invalid from contract')
        
        let a = rc.events[1].data.substring(0, 388) + '1' + rc.events[1].data.substring(389)

        calldata = await Web3EthAbi.encodeParameters(['address', 'bytes32[]', 'bytes'], [rc.events[1].address, rc.events[1].topics, a])
        await expect(daoExecutor.connect(admin).execute(calldata)).to.be.revertedWith('invalid proposal')

        a = rc.events[1].data.substring(0, 1290) + '1' + rc.events[1].data.substring(1291)
        calldata = await Web3EthAbi.encodeParameters(['address', 'bytes32[]', 'bytes'], [rc.events[1].address, rc.events[1].topics, a])
        // await expect(daoExecutor.connect(admin).execute(calldata)).to.be.revertedWith('invalid voter')

        a = rc.events[1].data.substring(0, 192) + '1' + rc.events[1].data.substring(193)
        calldata = await Web3EthAbi.encodeParameters(['address', 'bytes32[]', 'bytes'], [rc.events[1].address, rc.events[1].topics, a])
        await expect(daoExecutor.connect(admin).execute(calldata)).to.be.revertedWith('invalid governor type')
    })

    it('ScalableVote', async () => {
        await expect(scalableVotes.connect(user1).changeVoters([user1.address,user2.address])).to.be.revertedWith("Governor: onlyGovernance")
        await expect(scalableVotesCon.deploy([user1.address, AddressZero, user3.address], admin.address)).to.be.revertedWith('invalid voter')
        await expect(scalableVotesCon.deploy([user1.address, user1.address, user3.address], admin.address)).to.be.revertedWith('voter can not be repeated')
        await expect(scalableVotesCon.deploy([user1.address, user1.address, user3.address], AddressZero)).to.be.revertedWith('invalid governor')
        
        scalableVotes1 = await scalableVotesCon.deploy([user1.address, user2.address, user3.address], admin.address)
        await scalableVotes1.deployed()
        let tx = await scalableVotes1.connect(admin).changeVoters([user1.address, AddressZero, user1.address, user3.address, redeem.address, admin.address])
        expect(await scalableVotes1.getPastTotalSupply(tx.blockNumber - 1)).to.be.equal(4)
        tx = await scalableVotes1.connect(admin).changeVoters([user1.address, user1.address, user1.address, user3.address])
        expect(await scalableVotes1.getPastTotalSupply(tx.blockNumber - 1)).to.be.equal(2)
        expect(await scalableVotes1.getVotes(admin.address)).to.be.equal(0)
        expect(await scalableVotes1.getVotes(user3.address)).to.be.equal(1)
    })
})