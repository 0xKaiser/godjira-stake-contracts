const { expect } = require('chai')
const { ethers, artifacts } = require("hardhat")
const { advanceTime } = require('./utils')
const { Whitelist } = require('../lib')

const tokenPrice = ethers.utils.parseUnits('0.1', 18);

describe('Staking', () => {
  
  before(async () => {
    const users = await ethers.getSigners()

    this.tokenUri = "https://gladiators-metadata-api.herokuapp.com/api/token"
    this.deployer = users[0]
    this.users = users.slice(1)

    const genesis = await ethers.getContractFactory('Genesis')
    const mockNFT = await ethers.getContractFactory('MockNFT')

    this.mockNFT = await mockNFT.deploy()
    this.genesis = await genesis.deploy("genesis", "genesis", this.tokenUri, this.mockNFT.address)
    
    const gen2 = await ethers.getContractFactory('Gen2')
    this.gen2 = await gen2.deploy("gen2", "gen2", this.tokenUri)

    const jiraToken = await ethers.getContractFactory('JiraToken')
    this.jiraToken = await jiraToken.deploy()

    const stakingV1 = await ethers.getContractFactory('Staking')
    this.stakingV1 = await stakingV1.deploy()

    const Proxy = await ethers.getContractFactory("UnstructuredProxy")
    this.proxy = await Proxy.deploy()

    await this.proxy.deployed()
    await this.stakingV1.deployed()

    await this.proxy.upgradeTo(this.stakingV1.address)

    expect(await this.proxy.implementation())
      .to.equal(this.stakingV1.address)
    
    const { abi: abiV1 } = await artifacts.readArtifact("Staking")
    const proxyUpgraded = new ethers.Contract(this.proxy.address, abiV1, ethers.getDefaultProvider())
    this.proxyUpgraded = await proxyUpgraded.connect(this.deployer)
    this.proxyUpgraded.initialize(this.genesis.address, this.gen2.address, this.jiraToken.address)

    this.jiraToken.connect(this.deployer).modifyStakingOwner(this.proxyUpgraded.address)

    await this.genesis.connect(this.deployer).mint([10, 20])
    await this.mockNFT.connect(this.deployer).mint(this.users[1].address, 10)
    await this.mockNFT.connect(this.deployer).mint(this.users[1].address, 20)

    await this.mockNFT.connect(this.users[1]).setApprovalForAll(this.genesis.address, true)
    await this.genesis.connect(this.users[1]).claim([10, 20])

    await this.gen2.connect(this.users[1]).mint(10)
  })

  it('stake function succeeds', async () => {
    await advanceTime(5 * 3600 * 24)
    const whitelist = new Whitelist({ contract: this.proxyUpgraded, signer: this.users[1] })
    const whitelisted = await whitelist.createWhiteList(this.users[1].address, 10, 1, [1, 2, 3], [1, 2, 3])
    console.log(whitelisted)
    await this.proxyUpgraded.connect(this.deployer).modifySigner(this.users[1].address)
    await this.proxyUpgraded.connect(this.users[1]).stake(whitelisted)
    return
    const owner = await this.skyIsland.ownerOf(500)
    expect(owner).to.equal(this.users[2].address)
    
    await this.skyIsland.connect(this.users[2]).approve(this.proxyUpgraded.address, 500)
    const tx = await this.proxyUpgraded.connect(this.users[2]).stake([500])
    const rc = await tx.wait();
    const event = rc.events.find(event => event.event === 'Staked');
    const getStakingTokedId = await this.proxyUpgraded.stakeInfos(event.args.ticketNumbers[0])
    expect(500).to.equal(getStakingTokedId.tokenId)
  })

  return;
  it('claim function succeeds', async () => {
    await advanceTime(5 * 3600 * 24)
    
    await this.proxyUpgraded.connect(this.users[2]).claim(1, 2000)
    const balance = await this.skyVerseToken.balanceOf(this.users[2].address)
    expect(2000).to.equal(balance)

    await this.proxyUpgraded.connect(this.users[2]).claim(1, 1000)
    const balance1 = await this.skyVerseToken.balanceOf(this.users[2].address)
    expect(3000).to.equal(balance1)
    
    const getReward = await this.proxyUpgraded.connect(this.users[2]).getStakeReward()
    expect(2000).to.equal(getReward)
  })

  it('claim function succeeds', async () => {
    await this.proxyUpgraded.connect(this.users[2]).claimAll()
    const balance = await this.skyVerseToken.balanceOf(this.users[2].address)
    expect(5000).to.equal(balance)

    const getReward = await this.proxyUpgraded.connect(this.users[2]).getStakeReward()
    expect(0).to.equal(getReward)
  })

  it('unStake function succeeds', async () => {
    await this.proxyUpgraded.connect(this.users[2]).unStake([1])
    const owner = await this.skyIsland.ownerOf(500)
    expect(this.users[2].address).to.equal(owner)
  })

  it('mint + stake function succeeds', async () => {
    await advanceTime(5 * 3600 * 24)
    const whitelist = new Whitelist({ contract: this.skyIsland, signer: this.users[3] })
    const whitelisted = await whitelist.createWhiteList(this.users[3].address, 501, 1)
    await this.skyIsland.connect(this.deployer).modifySigner(this.users[3].address)
    await this.skyIsland.connect(this.users[3]).mint(whitelisted, true, {value: tokenPrice})
    const owner = await this.skyIsland.ownerOf(501)
    expect(owner).to.equal(this.proxyUpgraded.address)
  })
})
