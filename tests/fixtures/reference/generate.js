// Regenerates pose_expected.json with the official Spine 4.2 runtime.
//
//   npm install --no-save @esotericsoftware/spine-core@4.2.120
//   node tests/fixtures/reference/generate.js
//
// The checked-in output was generated with @esotericsoftware/spine-core 4.2.120.
const fs = require("fs");
const path = require("path");
const spine = require("@esotericsoftware/spine-core");

const here = __dirname;
const input = JSON.parse(fs.readFileSync(path.join(here, "pose_input.json")));

// The fixture intentionally has no attachments; fail loudly if that changes.
const loader = {
  newRegionAttachment: () => { throw new Error("fixture must not contain attachments"); },
  newMeshAttachment: () => { throw new Error("fixture must not contain attachments"); },
  newBoundingBoxAttachment: () => { throw new Error("fixture must not contain attachments"); },
  newPathAttachment: () => { throw new Error("fixture must not contain attachments"); },
  newPointAttachment: () => { throw new Error("fixture must not contain attachments"); },
  newClippingAttachment: () => { throw new Error("fixture must not contain attachments"); },
};

const skeletonData = new spine.SkeletonJson(loader).readSkeletonData(input);
const skeleton = new spine.Skeleton(skeletonData);
const state = new spine.AnimationState(new spine.AnimationStateData(skeletonData));
state.setAnimation(0, "move", false);

const times = [0, 0.25, 0.5, 0.75, 1];
const output = { times, bones: {} };
let previousTime = 0;

for (const time of times) {
  state.update(time - previousTime);
  state.apply(skeleton);
  skeleton.updateWorldTransform(spine.Physics.update);
  previousTime = time;

  output.bones[time] = {};
  for (const bone of skeleton.bones) {
    output.bones[time][bone.data.name] = [
      bone.worldX, bone.worldY, bone.a, bone.b, bone.c, bone.d,
    ];
  }
}

fs.writeFileSync(path.join(here, "pose_expected.json"), JSON.stringify(output, null, 2) + "\n");
console.log("wrote pose_expected.json");
