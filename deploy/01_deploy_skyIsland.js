module.exports = async ({getNamedAccounts, deployments}) => {
  const {deploy} = deployments;
  const {deployer} = await getNamedAccounts();

  await deploy('SkyIsland', {
    from: deployer,
    args: [
      10
    ],
    log: true,
  });
};
module.exports.tags = ['SkyIsland'];
