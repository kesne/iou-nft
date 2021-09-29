import expect from "expect";
import { ethers } from "hardhat";
import { Contract } from "ethers";

describe("IOweYou", () => {
  let iOweYou: Contract;
  before(async () => {
    const IOweYou = await ethers.getContractFactory("IOweYou");
    iOweYou = await IOweYou.deploy("test://");
    iOweYou.deployed();
  });

  it("should not allow acccessing tokenURI for tokens not yet minted", async () => {
    // Token is not yet minted, accessing the token URI should fail:
    await expect(async () => {
      await iOweYou.tokenURI(999);
    }).rejects.toEqual(expect.anything());
  });

  it("should reject creating an IOU with yourself", async () => {
    await expect(async () => {
      const [owner] = await ethers.getSigners();

      const createTx = await iOweYou.create(
        owner.address,
        "I promise to do something."
      );

      await createTx.wait();
    }).rejects.toMatchObject({
      message: expect.stringContaining("You cannot make an IOU to yourself."),
    });
  });

  it("should allow for creating an IOU", async () => {
    const [creator, receiver, uninvolved] = await ethers.getSigners();

    const promise = "I promise to do something.";

    const iou = await iOweYou.create(
      receiver.address,
      "I promise to do something."
    );
    await iou.wait();

    const creatorBalance = await iOweYou.balanceOf(creator.address);
    const receiverBalance = await iOweYou.balanceOf(receiver.address);

    // We should not mint a NFT on the sender side
    expect(creatorBalance.toNumber()).toBe(0);
    // We should mint an NFT the receiver
    expect(receiverBalance.toNumber()).toBe(1);

    const tokenId = await iOweYou.tokenOfOwnerByIndex(receiver.address, 0);

    // Expect token URI to exist:
    expect(await iOweYou.tokenURI(tokenId)).toEqual(`test://${tokenId}`);

    // Expect the IOU to be the correct shape:
    let iouState = await iOweYou.getIOU(tokenId);
    expect(iouState.owed).toBe(promise);
    expect(iouState.owed).toBe(promise);
    expect(iouState.creator).toBe(creator.address);
    expect(iouState.receiver).toBe(receiver.address);
    expect(iouState.creatorCompleted).toBe(false);
    expect(iouState.receiverCompleted).toBe(false);

    // Complete it from the creator side:
    const completeTx = await iOweYou.complete(tokenId);
    await completeTx.wait();
    iouState = await iOweYou.getIOU(tokenId);
    expect(iouState.creatorCompleted).toBe(true);
    expect(iouState.receiverCompleted).toBe(false);

    // Attempt to complete it as an uninvolved party:
    await expect(async () => {
      await iOweYou.connect(uninvolved).complete(tokenId);
    }).rejects.toMatchObject({
      message: expect.stringContaining("You can only complete your own IOU"),
    });

    // Complete it as the receiver
    const receiverCompleteTx = await iOweYou
      .connect(receiver)
      .complete(tokenId);
    await receiverCompleteTx.wait();

    // Attempting should get it should throw, as the token has been burnt:
    await expect(async () => {
      await iOweYou.getIOU(tokenId);
    }).rejects.toMatchObject({
      message: expect.stringContaining("IOU does not exist."),
    });

    // Should be burned:
    expect((await iOweYou.balanceOf(receiver.address)).toNumber()).toBe(0);
  });
});
