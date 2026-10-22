// Regenerates the reference fixtures with the official Spine 4.2 runtime.
//
//   npm install --no-save @esotericsoftware/spine-core@4.2.120
//   node tests/fixtures/reference/generate.js
//
// The checked-in outputs were generated with @esotericsoftware/spine-core
// 4.2.120. None of these fixtures contain attachments.
const fs = require("fs");
const path = require("path");
const spine = require("@esotericsoftware/spine-core");

const here = __dirname;

const loader = {
  newRegionAttachment: () => { throw new Error("fixture must not contain attachments"); },
  newMeshAttachment: () => { throw new Error("fixture must not contain attachments"); },
  newBoundingBoxAttachment: () => { throw new Error("fixture must not contain attachments"); },
  newPathAttachment: () => { throw new Error("fixture must not contain attachments"); },
  newPointAttachment: () => { throw new Error("fixture must not contain attachments"); },
  newClippingAttachment: () => { throw new Error("fixture must not contain attachments"); },
};

const pathLoader = {
  newRegionAttachment: () => { throw new Error("path fixture must not contain regions"); },
  newMeshAttachment: () => { throw new Error("path fixture must not contain meshes"); },
  newBoundingBoxAttachment: () => { throw new Error("path fixture must not contain bounding boxes"); },
  newPathAttachment: (name) => new spine.PathAttachment(name),
  newPointAttachment: () => { throw new Error("path fixture must not contain points"); },
  newClippingAttachment: () => { throw new Error("path fixture must not contain clipping"); },
};

function readInput(name) {
  return JSON.parse(fs.readFileSync(path.join(here, name), "utf8"));
}

function writeOutput(name, value) {
  fs.writeFileSync(path.join(here, name), JSON.stringify(value, null, 2) + "\n");
}

function boneMatrices(skeleton) {
  const out = {};
  for (const bone of skeleton.bones) {
    out[bone.data.name] = [
      bone.worldX, bone.worldY, bone.a, bone.b, bone.c, bone.d,
    ];
  }
  return out;
}

function generatePose() {
  const input = readInput("pose_input.json");
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
    output.bones[time] = boneMatrices(skeleton);
  }

  writeOutput("pose_expected.json", output);
}

function generateTimelines() {
  const input = readInput("timeline_input.json");
  const skeletonData = new spine.SkeletonJson(loader).readSkeletonData(input);
  const output = {
    loop: { times: [], bones: {} },
    multitrack: { times: [], bones: {} },
  };

  {
    const skeleton = new spine.Skeleton(skeletonData);
    skeleton.setToSetupPose();
    const state = new spine.AnimationState(new spine.AnimationStateData(skeletonData));
    state.setAnimation(0, "loop", true);
    let previousTime = 0;
    for (const time of [0, 0.25, 0.5, 0.6, 0.75, 1.1, 1.4]) {
      state.update(time - previousTime);
      state.apply(skeleton);
      skeleton.updateWorldTransform(spine.Physics.update);
      previousTime = time;
      output.loop.times.push(time);
      output.loop.bones[time] = boneMatrices(skeleton);
    }
  }

  {
    const skeleton = new spine.Skeleton(skeletonData);
    skeleton.setToSetupPose();
    const state = new spine.AnimationState(new spine.AnimationStateData(skeletonData));
    state.setAnimation(0, "base", true);
    state.setAnimation(1, "overlay", true);
    state.tracks[1].alpha = 0.5;
    let previousTime = 0;
    for (const time of [0, 0.25, 0.5, 0.75, 1.1]) {
      state.update(time - previousTime);
      state.apply(skeleton);
      skeleton.updateWorldTransform(spine.Physics.update);
      previousTime = time;
      output.multitrack.times.push(time);
      output.multitrack.bones[time] = boneMatrices(skeleton);
    }
  }

  writeOutput("timeline_expected.json", output);
}

function generateIK() {
  const input = readInput("ik_input.json");
  const skeletonData = new spine.SkeletonJson(loader).readSkeletonData(input);
  const skeleton = new spine.Skeleton(skeletonData);
  skeleton.setToSetupPose();
  skeleton.updateWorldTransform(spine.Physics.update);

  const output = {};
  for (const bone of skeleton.bones) {
    output[bone.data.name] = [
      bone.worldX, bone.worldY, bone.a, bone.b, bone.c, bone.d, bone.rotation,
    ];
  }
  writeOutput("ik_expected.json", output);
}

function generateConstraintTimeline() {
  const input = readInput("constraint_input.json");
  const skeletonData = new spine.SkeletonJson(loader).readSkeletonData(input);
  const skeleton = new spine.Skeleton(skeletonData);
  skeleton.setToSetupPose();
  const state = new spine.AnimationState(new spine.AnimationStateData(skeletonData));
  state.setAnimation(0, "mix", false);

  const output = { times: [], bones: {} };
  let previousTime = 0;
  for (const time of [0, 0.25, 0.5, 0.75, 1]) {
    state.update(time - previousTime);
    state.apply(skeleton);
    skeleton.updateWorldTransform(spine.Physics.update);
    previousTime = time;
    output.times.push(time);
    output.bones[time] = boneMatrices(skeleton);
  }

  writeOutput("constraint_expected.json", output);
}

function generatePath() {
  const input = readInput("path_input.json");
  const skeletonData = new spine.SkeletonJson(pathLoader).readSkeletonData(input);
  const skeleton = new spine.Skeleton(skeletonData);
  skeleton.setToSetupPose();
  skeleton.updateWorldTransform(spine.Physics.update);

  const output = {};
  for (const bone of skeleton.bones) {
    output[bone.data.name] = [
      bone.worldX, bone.worldY, bone.a, bone.b, bone.c, bone.d,
    ];
  }
  writeOutput("path_expected.json", output);
}

function generatePhysics() {
  const input = readInput("physics_input.json");
  const skeletonData = new spine.SkeletonJson(loader).readSkeletonData(input);
  const skeleton = new spine.Skeleton(skeletonData);
  skeleton.setToSetupPose();
  // Match the runtime's initialization pass before the first animation frame.
  skeleton.updateWorldTransform(spine.Physics.update);

  const state = new spine.AnimationState(new spine.AnimationStateData(skeletonData));
  state.setAnimation(0, "move", true);
  const dt = 1 / 30;
  for (let i = 0; i < 30; i++) {
    state.update(dt);
    state.apply(skeleton);
    skeleton.update(dt);
    skeleton.updateWorldTransform(spine.Physics.update);
  }

  const output = {};
  for (const bone of skeleton.bones) {
    output[bone.data.name] = [
      bone.worldX, bone.worldY, bone.a, bone.b, bone.c, bone.d,
    ];
  }
  writeOutput("physics_expected.json", output);
}

generatePose();
generateTimelines();
generateIK();
generateConstraintTimeline();
generatePath();
generatePhysics();
console.log("wrote pose, timeline, IK, path, physics, and transform-constraint fixtures");
