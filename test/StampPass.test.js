const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("StampPass", function () {
  let sp, owner, alice, bob, carol;
  const CREATE_FEE = ethers.parseEther("0.001");
  const STAMP_FEE = ethers.parseEther("0.0005");

  beforeEach(async () => {
    [owner, alice, bob, carol] = await ethers.getSigners();
    const F = await ethers.getContractFactory("StampPass");
    sp = await F.deploy();
    await sp.waitForDeployment();
  });

  async function createDefault(signer = alice, slug = "coffee-shop") {
    return sp.connect(signer).createLocation(slug, "Coffee Shop", "A cozy place", "", { value: CREATE_FEE });
  }

  it("createLocation: requires fee", async () => {
    await expect(
      sp.connect(alice).createLocation("abc", "N", "", "", { value: 0 })
    ).to.be.revertedWith("fee");
  });

  it("createLocation: slug format validation", async () => {
    await expect(sp.connect(alice).createLocation("ab", "N", "", "", { value: CREATE_FEE })).to.be.revertedWith("slug");
    await expect(sp.connect(alice).createLocation("BAD_UP", "N", "", "", { value: CREATE_FEE })).to.be.revertedWith("slug");
    await expect(sp.connect(alice).createLocation("has space", "N", "", "", { value: CREATE_FEE })).to.be.revertedWith("slug");
    // Valid
    await expect(sp.connect(alice).createLocation("ok-slug-1", "N", "", "", { value: CREATE_FEE })).to.not.be.reverted;
  });

  it("createLocation: uniqueness", async () => {
    await createDefault(alice, "same");
    await expect(sp.connect(bob).createLocation("same", "X", "", "", { value: CREATE_FEE })).to.be.revertedWith("dup");
  });

  it("createLocation: name/desc/icon lengths", async () => {
    await expect(sp.connect(alice).createLocation("slug-a", "", "", "", { value: CREATE_FEE })).to.be.revertedWith("name");
    const long = "x".repeat(257);
    await expect(sp.connect(alice).createLocation("slug-b", "N", long, "", { value: CREATE_FEE })).to.be.revertedWith("desc");
    await expect(sp.connect(alice).createLocation("slug-c", "N", "", long, { value: CREATE_FEE })).to.be.revertedWith("icon");
  });

  it("collectStamp: requires fee & only once", async () => {
    await createDefault();
    await expect(sp.connect(bob).collectStamp(1, { value: 0 })).to.be.revertedWith("fee");
    await sp.connect(bob).collectStamp(1, { value: STAMP_FEE });
    await expect(sp.connect(bob).collectStamp(1, { value: STAMP_FEE })).to.be.revertedWith("have");
  });

  it("collectStamp: transfers 50% to creator", async () => {
    await createDefault(alice);
    const before = await ethers.provider.getBalance(alice.address);
    await sp.connect(bob).collectStamp(1, { value: STAMP_FEE });
    const after = await ethers.provider.getBalance(alice.address);
    expect(after - before).to.equal(STAMP_FEE / 2n);
  });

  it("stamperCount increments", async () => {
    await createDefault();
    await sp.connect(bob).collectStamp(1, { value: STAMP_FEE });
    await sp.connect(carol).collectStamp(1, { value: STAMP_FEE });
    const info = await sp.getLocation(1);
    expect(info.stamperCount).to.equal(2n);
  });

  it("slug lookup", async () => {
    await createDefault(alice, "findme");
    expect(await sp.getLocationBySlug("findme")).to.equal(1n);
    expect(await sp.getLocationBySlug("nope")).to.equal(0n);
  });

  it("hasStamp & timestamp recorded", async () => {
    await createDefault();
    expect(await sp.hasStamp(1, bob.address)).to.equal(false);
    const tx = await sp.connect(bob).collectStamp(1, { value: STAMP_FEE });
    const rc = await tx.wait();
    const blk = await ethers.provider.getBlock(rc.blockNumber);
    expect(await sp.hasStamp(1, bob.address)).to.equal(true);
    expect(await sp.getStamperTimestamp(1, bob.address)).to.equal(BigInt(blk.timestamp));
  });

  it("stamper list & user passport", async () => {
    await createDefault(alice, "loc1");
    await sp.connect(alice).createLocation("loc2", "L2", "", "", { value: CREATE_FEE });
    await sp.connect(bob).collectStamp(1, { value: STAMP_FEE });
    await sp.connect(bob).collectStamp(2, { value: STAMP_FEE });
    await sp.connect(carol).collectStamp(1, { value: STAMP_FEE });
    const s1 = await sp.getStampers(1);
    expect(s1.length).to.equal(2);
    expect(s1[0]).to.equal(bob.address);
    const bobStamps = await sp.getStamps(bob.address);
    expect(bobStamps.map(x => Number(x))).to.deep.equal([1, 2]);
    expect(await sp.stampCount(bob.address)).to.equal(2n);
  });

  it("getRecent returns newest first", async () => {
    for (let i = 0; i < 4; i++) {
      await sp.connect(alice).createLocation(`slug-${i}`, `N${i}`, "", "", { value: CREATE_FEE });
    }
    const r = await sp.getRecent(0, 10);
    expect(r.map(x => Number(x))).to.deep.equal([4, 3, 2, 1]);
    const r2 = await sp.getRecent(1, 2);
    expect(r2.map(x => Number(x))).to.deep.equal([3, 2]);
  });

  it("admin bounds enforced", async () => {
    await expect(sp.setCreateFee(ethers.parseEther("1.1"))).to.be.revertedWith("max");
    await expect(sp.setStampFee(ethers.parseEther("0.11"))).to.be.revertedWith("max");
    await expect(sp.setCreatorShareBps(8001)).to.be.revertedWith("max");
    await sp.setCreateFee(ethers.parseEther("0.5"));
    expect(await sp.createFee()).to.equal(ethers.parseEther("0.5"));
  });

  it("pause blocks writes", async () => {
    await sp.pause();
    await expect(sp.connect(alice).createLocation("x-slug", "N", "", "", { value: CREATE_FEE })).to.be.reverted;
    await sp.unpause();
    await expect(sp.connect(alice).createLocation("x-slug", "N", "", "", { value: CREATE_FEE })).to.not.be.reverted;
  });

  it("non-owner cannot admin", async () => {
    await expect(sp.connect(alice).setCreateFee(0)).to.be.reverted;
    await expect(sp.connect(alice).pause()).to.be.reverted;
    await expect(sp.connect(alice).withdrawFees(alice.address)).to.be.reverted;
  });

  it("withdrawFees moves platform share to owner", async () => {
    await createDefault();
    await sp.connect(bob).collectStamp(1, { value: STAMP_FEE });
    // Contract holds: createFee + platform half of stamp
    const bal = await ethers.provider.getBalance(await sp.getAddress());
    expect(bal).to.equal(CREATE_FEE + STAMP_FEE / 2n);
    await sp.withdrawFees(owner.address);
    expect(await ethers.provider.getBalance(await sp.getAddress())).to.equal(0n);
  });
});
