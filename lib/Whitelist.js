const ethers = require('ethers')

const SIGNING_DOMAIN_NAME = "Gen"
const SIGNING_DOMAIN_VERSION = "1"


class Whitelist {
  constructor({ contract, signer }) {
    this.contract = contract
    this.signer = signer
  }

  async createWhiteList(whiteListAddress, genTokenId, genMultiplier, gen2TokenIds, gen2Earnings) {
    const value = { whiteListAddress, genTokenId, genMultiplier, gen2TokenIds, gen2Earnings }
    const domain = await this._signingDomain()
    const types = {
      whitelisted: [
        {name: "whiteListAddress", type: "address"},
        {name: "genTokenId", type: "uint256"},
        {name: "genMultiplier", type: "string"},
        {name: "gen2TokenIds", type: "uint256[]"},
        {name: "gen2Earnings", type: "string[]"}
      ]
    }
    const signature = await this.signer._signTypedData(domain, types, value)
    return {
      ...value,
      signature,
    }
  }

  async _signingDomain() {
    if (this._domain != null) {
      return this._domain
    }
    const chainId = await this.contract.getChainID()
    this._domain = {
      name: SIGNING_DOMAIN_NAME,
      version: SIGNING_DOMAIN_VERSION,
      verifyingContract: this.contract.address,
      chainId,
    }
    return this._domain
  }
}

module.exports = {
  Whitelist
}