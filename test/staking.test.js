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

  it('stake function succeeds : addNewBag', async () => {
    await advanceTime(5 * 3600 * 24)
    // const whitelist = new Whitelist({ contract: this.stakingV1, signer: this.users[1] })
    // const whitelisted = await whitelist.createWhiteList(this.users[1].address, 10, 1, [1, 2, 3], [1, 2, 3])

    const bags =
    [  
      {
        genTokenId: 10,
        genRarity: 1,
        gen2TokenIds: [1,2,3],
        gen2Rarities: [1,2,3],
        unclaimedBalance: 0,
        lastStateChange: 0
      }
    ]

    await this.proxyUpgraded.connect(this.deployer).modifySigner(this.users[1].address)

    await this.genesis.connect(this.users[1]).approve(this.proxyUpgraded.address, 10)
    await this.gen2.connect(this.users[1]).approve(this.proxyUpgraded.address, 1)
    await this.gen2.connect(this.users[1]).approve(this.proxyUpgraded.address, 2)
    await this.gen2.connect(this.users[1]).approve(this.proxyUpgraded.address, 3)
    
    const tx = await this.proxyUpgraded.connect(this.users[1]).stake(bags, [true], [0])
    const rc = await tx.wait()
    const event = rc.events.find(event => event.event === 'Staked')
    const getBag = await this.proxyUpgraded.bags(event.args.bagId)
    expect(ethers.BigNumber.from("10")).to.equal(getBag.genTokenId)
  })

  it('claim function succeeds', async () => {
    await advanceTime(5 * 3600 * 24)
    
    await this.proxyUpgraded.connect(this.users[1]).claim()
    const balance = await this.jiraToken.balanceOf(this.users[1].address)
    expect(207).to.equal(balance)
  })

  it('unstake function succeeds', async () => {
    await this.proxyUpgraded.connect(this.users[1]).unstake(
      [1],
      [{
        id: 10
      }],
      [{
        ids: [1, 2, 3]
      }]
    )
    const owner = await this.gen2.ownerOf(1)
    expect(this.users[1].address).to.equal(owner)
  })

  it('addBagInfo function succeeds', async () => {
    const bags =
    [  
      {
        genTokenId: 20,
        genRarity: 2,
        gen2TokenIds: [4],
        gen2Rarities: [3],
        unclaimedBalance: 0,
        lastStateChange: 0
      }
    ]

    await this.proxyUpgraded.connect(this.deployer).modifySigner(this.users[1].address)

    await this.genesis.connect(this.users[1]).approve(this.proxyUpgraded.address, 20)
    await this.gen2.connect(this.users[1]).approve(this.proxyUpgraded.address, 4)
    
    await this.proxyUpgraded.connect(this.users[1]).stake(bags, [true], [0])

    await advanceTime(5 * 3600 * 24)
  
    const addBagInfo = [
      {
        genTokenId: 0,
        genRarity: 0,
        gen2TokenIds: [5, 6],
        gen2Rarities: [1, 2],
        unclaimedBalance: 0,
        lastStateChange: 0
      }
    ]
    await this.proxyUpgraded.connect(this.users[1]).stake(addBagInfo, [false], [2])

    await advanceTime(5 * 3600 * 24)
    await this.proxyUpgraded.connect(this.users[1]).claim()
    const balance = await this.jiraToken.balanceOf(this.users[1].address)

    expect(637).to.equal(balance)
  })
})
