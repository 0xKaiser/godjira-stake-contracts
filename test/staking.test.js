const { expect } = require('chai')
const { ethers, artifacts } = require("hardhat")
const { advanceTime } = require('./utils')
const { Whitelist } = require('../lib')

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
    // const whitelist = new Whitelist({ contract: this.stakingV1, signer: this.users[1] })
    // const whitelisted = await whitelist.createWhiteList(this.users[1].address, 10, 1, [1, 2, 3], [1, 2, 3])

    const stakeInfo =
    [  {
        genTokenId: 10,
        genRarity: 1,
        gen2TokenIds: [1,2,3],
        gen2Rarities: [1,2,3],
        reward: 0,
        since: 0
      }
    ]

    await this.proxyUpgraded.connect(this.deployer).modifySigner(this.users[1].address)

    await this.genesis.connect(this.users[1]).approve(this.proxyUpgraded.address, 10)
    await this.gen2.connect(this.users[1]).approve(this.proxyUpgraded.address, 1)
    await this.gen2.connect(this.users[1]).approve(this.proxyUpgraded.address, 2)
    await this.gen2.connect(this.users[1]).approve(this.proxyUpgraded.address, 3)
    
    
    const tx = await this.proxyUpgraded.connect(this.users[1]).stake(stakeInfo)
    const rc = await tx.wait()
    const event = rc.events.find(event => event.event === 'Staked')
    const getStakingInfo = await this.proxyUpgraded.stakeInfos(event.args.bagId)
    expect(ethers.BigNumber.from("10")).to.equal(getStakingInfo.genTokenId)
  })

  it('claim function succeeds', async () => {
    await advanceTime(5 * 3600 * 24)
    
    await this.proxyUpgraded.connect(this.users[1]).claim(1, 100)
    const balance = await this.jiraToken.balanceOf(this.users[1].address)
    expect(100).to.equal(balance)

    await this.proxyUpgraded.connect(this.users[1]).claim(1, 10)
    const balance1 = await this.jiraToken.balanceOf(this.users[1].address)
    expect(110).to.equal(balance1)
    
    const getReward = await this.proxyUpgraded.connect(this.users[1]).getStakeReward()
    expect(97).to.equal(getReward)
  })

  it('claimAll function succeeds', async () => {
    await this.proxyUpgraded.connect(this.users[1]).claimAll()
    const balance = await this.jiraToken.balanceOf(this.users[1].address)
    expect(207).to.equal(balance)

    const getReward = await this.proxyUpgraded.connect(this.users[2]).getStakeReward()
    expect(0).to.equal(getReward)
  })

  
  it('unStake function succeeds', async () => {
    await this.proxyUpgraded.connect(this.users[1]).unStake([1])
    const owner = await this.genesis.ownerOf(10)
    expect(this.users[1].address).to.equal(owner)
  })

  it('addBagInfo function succeeds', async () => {
    const stakeInfo =
    [  {
        genTokenId: 20,
        genRarity: 2,
        gen2TokenIds: [4],
        gen2Rarities: [3],
        reward: 0,
        since: 0
      }
    ]

    await this.proxyUpgraded.connect(this.deployer).modifySigner(this.users[1].address)

    await this.genesis.connect(this.users[1]).approve(this.proxyUpgraded.address, 20)
    await this.gen2.connect(this.users[1]).approve(this.proxyUpgraded.address, 4)
    
    await this.proxyUpgraded.connect(this.users[1]).stake(stakeInfo)

    await advanceTime(5 * 3600 * 24)
  
    await this.proxyUpgraded.connect(this.users[1]).addBagInfo(2, [5, 6], [1, 2])

    await advanceTime(5 * 3600 * 24)
    await this.proxyUpgraded.connect(this.users[1]).claimAll()
    const balance = await this.jiraToken.balanceOf(this.users[1].address)

    expect(948).to.equal(balance)
  })
})
