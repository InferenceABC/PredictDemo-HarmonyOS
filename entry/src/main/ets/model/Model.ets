/*
 * Copyright (c) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { mindSporeLite } from '@kit.MindSporeLiteKit'
import Logger from '../common/utils/Logger';

export default async function modelPredict(
  modelBuffer: ArrayBuffer, inputsBuffer: ArrayBuffer[]): Promise<mindSporeLite.MSTensor[]> {

  let context: mindSporeLite.Context = {};
  context.target = ['cpu'];
  context.cpu = {}
  context.cpu.threadNum = 4;
  context.cpu.threadAffinityMode = 1;
  context.cpu.threadAffinityCoreList = [0, 1, 2]
  context.cpu.precisionMode = 'enforce_fp32';
  // context.target = ['nnrt']

  let msLiteModel: mindSporeLite.Model = await mindSporeLite.loadModelFromBuffer(modelBuffer, context);
  Logger.info('=========DEMO_LOG: Load Model=====');
  let modelInputs: mindSporeLite.MSTensor[] = msLiteModel.getInputs();
  console.info('=========DEMO_LOG: Inputs Shape =====', modelInputs[0].shape.toString())
  Logger.info('=========DEMO_LOG: Init modelInputs=====');
  for (let i = 0; i < inputsBuffer.length; i++) {
    let inputBuffer = inputsBuffer[i];
    if (inputBuffer != null) {
      modelInputs[i].setData(inputBuffer as ArrayBuffer);
    }
  }
  Logger.info('=========DEMO_LOG: Set Data=====');

  Logger.info('=========MS_LITE_LOG: MS_LITE predict time start=====');
  let modelOutputs: mindSporeLite.MSTensor[] = await msLiteModel.predict(modelInputs);
  Logger.info('=========MS_LITE_LOG: MS_LITE predict time end=====');
  return modelOutputs;

}

export async function modelTrain(
  modelBuffer: ArrayBuffer
) {
  mindSporeLite.loadTrainModelFromBuffer(modelBuffer).then((mindSporeLiteModel : mindSporeLite.Model) => {
    mindSporeLiteModel.trainMode = true;

    let modelInputs : mindSporeLite.MSTensor[] = mindSporeLiteModel.getInputs();
    console.info(modelInputs[0].name);
    mindSporeLiteModel.runStep(modelInputs)

  })

}


