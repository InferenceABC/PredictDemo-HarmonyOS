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

import modelPredict from '../model/Model';
import Logger from '../common/utils/Logger'
import { resourceManager } from '@kit.LocalizationKit'
import { fileIo } from '@kit.CoreFileKit'
import { CommonConstants } from '../common/constants/CommonConstants';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common, Want } from '@kit.AbilityKit';
import { fileIo as fs, ReadOptions, WriteOptions, Filter, ListFileOptions} from '@kit.CoreFileKit';

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function generateModelChoiceString(out: Float32Array): string {
  // 定义前4个模型对应的名称
  const modelNames = [
    'face_det_damofd_10g',
    'face_det_retina',
    'face_det_damofd_2.5g',
    'face_det_damofd_34g'
  ];

  // 1. 【安全检查】处理数组越界风险
  // 如果数组不存在，或者长度小于我们需要比较的模型数量（4个），直接返回错误信息
  if (!out || out.length < modelNames.length) {
    return `错误：模型输出长度不足 (需至少${modelNames.length}位，实际${out ? out.length : 0}位)`;
  }

  let maxScore = -Infinity;
  let bestModelName = "";
  const scoreStrings: string[] = [];

  // 2. 遍历前4个模型，收集分数并寻找最大值
  for (let i = 0; i < modelNames.length; i++) {
    const currentScore = out[i];
    const currentName = modelNames[i];

    // 格式化当前分数用于展示 (例如 "face_det_damofd: 0.8845")
    scoreStrings.push(`${currentName}: ${currentScore.toFixed(4)}`);

    // 更新最大值逻辑
    if (currentScore > maxScore) {
      maxScore = currentScore;
      bestModelName = currentName;
    }
  }

  // 3. 构建结果字符串
  // 第一行：用中文逗号连接所有分数详情
  const scoreLine = scoreStrings.join("\n");

  // 第二行：显示最终选择
  const choiceLine = `选择 ${bestModelName} 模型，分数为 ${maxScore.toFixed(4)}`;

  // 使用 \n 实现换行
  return scoreLine + '\n' + choiceLine;
}

// 1. 定义包含 ID 的模型元数据接口
interface EnhanceModelInfo {
  id: number;      // 新增：1-9 的固定 ID
  index: number;   // 张量中的索引
  name: string;    // 模型名称
  group: string;   // 组名描述
  desc: string;    // 描述
}

// 2. 获胜者信息类，也携带 ID
class WinnerInfo {
  id: number = 0;      // 新增 ID
  name: string = '';
  score: number = 0;
  desc: string = '';
  group: string = '';
}

/**
 * 生成多模型推荐排序字符串
 * @param out 模型输出的 Float32Array
 * @param enableThreshold 是否开启人脸检测阈值判断 (默认为 true)
 * true: 分数 >= 0.3 才能排第一，否则可能不显示或提示无效
 * false: 不管分数多低，人脸组的第一名强制排在总榜第一
 */
function generateEnhanceRankString(out: Float32Array, enableThreshold: boolean = false): string {

  // === 定义 9 个模型的固定 ID (1-9) 和索引映射 ===
  const models: EnhanceModelInfo[] = [
    // --- 人脸检测组 (ID 1-4) ---
    { id: 1, index: 0, name: '人脸检测-Damoyolo', group: '人脸检测', desc: '人脸检测器' },
    { id: 2, index: 1, name: '人脸检测-RetinaFace', group: '人脸检测', desc: '人脸检测器' },
    { id: 3, index: 2, name: '人脸检测-Damofd 2.5G', group: '人脸检测', desc: '轻量版' },
    { id: 4, index: 3, name: '人脸检测-Damofd 3.4G', group: '人脸检测', desc: '标准版' },

    // --- 图像调色组 (ID 5-6) ---
    { id: 5, index: 12, name: '图像调色-CSRNet', group: '图像调色', desc: '色彩增强' },
    { id: 6, index: 13, name: '图像调色-DeepLPFNet', group: '9图像调色', desc: '细节增强' },

    // --- 图像去噪组 (ID 7) ---
    { id: 7, index: 14, name: '图像去噪-NAFNet', group: '图像去噪', desc: '去噪' },

    // --- 人像美化组 (ID 8-9) ---
    { id: 8, index: 15, name: '人像美化-UNet', group: '11人像美化', desc: '美肤' },
    { id: 9, index: 16, name: '人像美化-FBBR', group: '11人像美化', desc: '塑形' }
  ];

  // 1. 【安全检查】
  if (!out || out.length <= 16) {
    return `错误：模型输出长度不足 (需至少17位，实际${out ? out.length : 0}位)`;
  }

  // 2. 【第一部分】构建原始分数详情 (显示 ID 1-9)
  let rawScoreLines: string[] = [];
  models.forEach(m => {
    // 格式: [ID:1] Damoyolo: 0.1234
    rawScoreLines.push(`[ID:${m.id}] ${m.name}: ${out[m.index].toFixed(4)}`);
  });
  const allScoresStr = "=== 原始分数 (ID 1-9) ===\n" + rawScoreLines.join("\n");


  // 3. 【第二部分】核心逻辑：各组内部选拔

  // ---------------------------------------------------------
  // 【A】人脸检测组 (ID 1-4) 选拔
  // ---------------------------------------------------------
  let faceWinner: WinnerInfo | null = null;
  let maxFaceScore = -Infinity;
  let bestFaceModel: EnhanceModelInfo | null = null;

  // 遍历前 4 个模型 (数组下标 0-3)
  for (let i = 0; i < 4; i++) {
    const m = models[i]; // 获取 ID 1-4 的模型元数据
    const score = out[m.index];
    if (score > maxFaceScore) {
      maxFaceScore = score;
      bestFaceModel = m;
    }
  }

  // 阈值判断逻辑
  if (bestFaceModel !== null) {
    const isScoreValid = maxFaceScore >= 0.3;

    // 如果 开启了阈值检查 且 分数不达标，则 faceWinner 为 null
    // 否则 (关闭阈值 或 分数达标)，选出胜者
    if (!enableThreshold || isScoreValid) {
      faceWinner = {
        id: bestFaceModel.id,
        name: bestFaceModel.name,
        score: maxFaceScore,
        desc: bestFaceModel.desc,
        group: bestFaceModel.group
      };
    }
  }

  // ---------------------------------------------------------
  // 【B】图像调色组 (ID 5 vs 6)
  // ---------------------------------------------------------
  let winner9: WinnerInfo;
  const m5 = models[4]; // CSRNet
  const m6 = models[5]; // DeepLPFNet
  const s5 = out[m5.index];
  const s6 = out[m6.index];

  if (s5 >= s6) {
    winner9 = { id: m5.id, name: m5.name, score: s5, desc: m5.desc, group: m5.group };
  } else {
    winner9 = { id: m6.id, name: m6.name, score: s6, desc: m6.desc, group: m6.group };
  }

  // ---------------------------------------------------------
  // 【C】图像去噪组 (ID 7)
  // ---------------------------------------------------------
  const m7 = models[6]; // NAFNet
  let winner10: WinnerInfo = {
    id: m7.id, name: m7.name, score: out[m7.index], desc: m7.desc, group: m7.group
  };

  // ---------------------------------------------------------
  // 【D】人像美化组 (ID 8 vs 9)
  // ---------------------------------------------------------
  let winner11: WinnerInfo;
  const m8 = models[7]; // UNet
  const m9 = models[8]; // FBBR
  const s8 = out[m8.index];
  const s9 = out[m9.index];

  if (s8 >= s9) {
    winner11 = { id: m8.id, name: m8.name, score: s8, desc: m8.desc, group: m8.group };
  } else {
    winner11 = { id: m9.id, name: m9.name, score: s9, desc: m9.desc, group: m9.group };
  }


  // 4. 【第三部分】总排序逻辑

  // 步骤 1: 对 3 个增强任务的胜者进行降序排序
  let enhanceList: WinnerInfo[] = [winner9, winner10, winner11];
  enhanceList.sort((a, b) => b.score - a.score);

  // 步骤 2: 构建最终列表
  let finalList: WinnerInfo[] = [];

  // 如果有人脸检测胜者 (根据上面的逻辑，可能是分数够高，或者是关闭了阈值限制)，排第一
  if (faceWinner !== null) {
    finalList.push(faceWinner);
  }

  // 追加增强模型
  finalList = finalList.concat(enhanceList);


  // 5. 【第四部分】构建结果字符串
  let choiceLines: string[] = [];
  choiceLines.push("=== 推荐执行顺序 ===");

  if (faceWinner === null && enableThreshold) {
    choiceLines.push("提示：未检测到有效人脸 (ID 1-4 分数均 < 0.3)");
  }

  for (let i = 0; i < finalList.length; i++) {
    const item = finalList[i];
    // 格式： 1. [ID:3] Damofd 2.5G: 0.8888
    choiceLines.push(`${i + 1}. [ID:${item.id}] ${item.name}+: ${item.score.toFixed(4)}`);
  }

  return allScoresStr + '\n\n' + choiceLines.join("\n");
}

@Entry
@Component
struct Index {
  @State currentMode: number = 0;
  @State uris: Array<string> = [];
  @State maxIndexArray: Array<number> = [];
  @State fileNameShow: number = 0;
  @State photoShow: number = 0;
  @State fileName: string = '';
  @State predictResultShow: number = 0;
  @State predictText: string = '';
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  async predictInput(): Promise<void> {
    this.fileNameShow = 1;
    this.photoShow = 0;
    this.uris = [];
    this.predictResultShow = 1;


    let context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    let filesDir = context.filesDir;
    let datasetDir = filesDir +'/data_archive/250801_damo_emb'
    let photoDir = filesDir +'/data_archive/250801_pictures'


    let listFileOption: ListFileOptions = {
      recursion: false,
      listNum: 0,
      filter: {
        suffix: [".txt"]
      }
    };
    let filenames = fs.listFileSync(datasetDir, listFileOption);

    let resMgr: resourceManager.ResourceManager = this.context.getApplicationContext().resourceManager;
    let modelBuffer = await resMgr.getRawFileContent(CommonConstants.MODEL_NAME)

    for (let i = 0; i < filenames.length; i++) {
      // 显示逻辑
      this.photoShow = 1
      this.fileName = filenames[i].replace(/\.txt$/, '')
      let imagePath = 'file://' + photoDir + '/' + this.fileName;
      this.uris = [imagePath];

      let filePath = datasetDir + '/' + filenames[i]

      // 使用 fs.readTextSync，它直接返回解码后的字符串
      let textContent: string = fs.readTextSync(filePath, {
        // 确保指定正确的编码，默认为 'utf-8'
        encoding: 'utf-8'
      })
      console.log('The content of file', textContent)

      const numberArray: Array<number> = textContent
        .split(',')
        .map(s => parseFloat(s));

      // 2. 使用数字数组（Iterable<number>）创建 Float32Array
      const inputArray: Float32Array = new Float32Array(numberArray);
      console.log("=========DEMO_LOG: Input Data=====", inputArray)

      let output = await modelPredict(modelBuffer.buffer.slice(0), [inputArray.buffer])
      //
      let out = new Float32Array(output[0].getData());

      console.log("=========DEMO_LOG: Output Data=====", out)

      if (this.currentMode === 0) {
        // 模式 0: 目标检测 (前4个模型对比)
        this.predictText = generateModelChoiceString(out);
      } else {
        // 模式 1: 图像增强 (9,10,11组排序)
        this.predictText = generateEnhanceRankString(out);
      }

      await sleep(100)

    }

  }

  async testOneInput(): Promise<void> {
    this.fileNameShow = 1;
    this.photoShow = 0;
    this.uris = [];
    this.predictResultShow = 1;


    let context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    let filesDir = context.filesDir;
    let datasetDir = filesDir + '/data_archive/250801_damoyolo_emb'


    let listFileOption: ListFileOptions = {
      recursion: false,
      listNum: 0,
      filter: {
        suffix: [".txt"]
      }
    };
    let filenames = fs.listFileSync(datasetDir, listFileOption);


    // TODO 批量处理
    // let batchSize = 8
    //
    // for (let i = 0; i < filenames.length; i += batchSize) {
    //   // 获取当前批次的文件（最多8个）
    //   const batch = filenames.slice(i, i + batchSize);
    //   console.info(`Processing batch ${i / batchSize + 1}:`, batch);
    //
    //   // 并行处理当前批次的所有文件
    //   const batchPromises = batch.map(filename =>
    //   {getArrayByUriDebug(`${datasetDir}/${filename}`)}
    //   );
    //
    //   // 等待当前批次全部完成
    //   const batchResults = await Promise.all(batchPromises);
    //
    //   // 处理结果（过滤掉失败的null值）
    //   const successfulInputs = batchResults.filter(input => input !== null);
    //   console.info(`Batch ${i / batchSize + 1} completed. Success count:`, successfulInputs.length);
    // }

    let resMgr: resourceManager.ResourceManager = this.context.getApplicationContext().resourceManager;
    let modelBuffer = await resMgr.getRawFileContent(CommonConstants.MODEL_NAME)

    for (let i = 0; i < filenames.length; i++) {
      this.fileName = filenames[i].replace(/\.txt$/, '.png')

      let filePath = datasetDir + '/' + filenames[i]

      // 使用 fs.readTextSync，它直接返回解码后的字符串
      let textContent: string = fs.readTextSync(filePath, {
        // 确保指定正确的编码，默认为 'utf-8'
        encoding: 'utf-8'
      })
      console.log('The content of file', textContent)

      const numberArray: Array<number> = textContent
        .split(',')
        .map(s => parseFloat(s));

      // 2. 使用数字数组（Iterable<number>）创建 Float32Array
      const inputArray: Float32Array = new Float32Array(numberArray);
      console.log("=========DEMO_LOG: Input Data=====", inputArray)


      let output = await modelPredict(modelBuffer.buffer.slice(0), [inputArray.buffer])
      //
      let out = new Float32Array(output[0].getData());

      console.log("=========DEMO_LOG: Output Data=====", out)

      if (this.currentMode === 0) {
        // 模式 0: 目标检测 (前4个模型对比)
        this.predictText = generateModelChoiceString(out);
      } else {
        // 模式 1: 图像增强 (9,10,11组排序)
        this.predictText = generateEnhanceRankString(out);
      }


    }
  }

  build() {

    Column(){
      Row() {
        Text("选择模式：").fontSize(16).fontWeight(FontWeight.Bold)

        // 选项1：目标检测
        Row() {
          Radio({ value: 'detection', group: 'modeGroup' })
            .checked(this.currentMode === 0)
            .onChange((isChecked: boolean) => {
              if (isChecked) {
                this.currentMode = 0; // 切换到目标检测
              }
            })
          Text('单模型任务').fontSize(14)
        }
        .margin({ right: 10 })

        // 选项2：图像增强
        Row() {
          Radio({ value: 'enhance', group: 'modeGroup' })
            .checked(this.currentMode === 1)
            .onChange((isChecked: boolean) => {
              if (isChecked) {
                this.currentMode = 1; // 切换到图像增强
              }
            })
          Text('多模型任务').fontSize(14)
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding(10)
      Text(this.currentMode === 0 ? "单模型任务" : "多模型任务")
        .width(CommonConstants.FULL_PERCENT)
        .font({
          size: $r('app.float.All_title_font_size'),
          weight: CommonConstants.FONT_WEIGHT_700
        })
        .margin({
          top: $r('app.float.title_margin_top'),
          left: $r('app.float.title_margin_left'),
          bottom: $r('app.float.title_margin_bottom')
        })
      Text(this.currentMode === 0 ? "人脸框检测模型选择" : "人像优化多模型任务选择")
        .width(CommonConstants.FULL_PERCENT)
        .font({
          size: $r('app.float.Sub_title_font_size'),
          weight: CommonConstants.FONT_WEIGHT_700
        })
        .margin({
          left: $r('app.float.title_margin_left'),
          bottom: $r('app.float.title_margin_bottom')
        })
      if(this.fileNameShow){
        Text(this.fileName)
          .width($r('app.string.EntryAbility_label'))
          .font({
            size: $r('app.float.All_image_name_font_size'),
            weight: CommonConstants.FONT_WEIGHT_700
          })
      }
      if(this.photoShow){
        Image(this.uris[0])
          .height($r('app.float.image_height'))
          .objectFit(ImageFit.Contain)
          .borderRadius($r('sys.float.corner_radius_level10'))
          .margin({
            bottom: $r('app.float.image_margin_bottom')
          })
      }
      if(this.predictResultShow){
        Text(this.predictText)
          .font({
            size: "16fp"
          })
      } else {

      }
      Button('250801数据集测试')
        .width($r('app.float.button_width'))
        .height($r('app.float.button_height'))
        .margin({
          top: $r('app.float.button_margin_top')
        })
        .onClick(()=>{
          this.predictInput()
        })
      Button('单图测试（测试用）')
        .width($r('app.float.button_width'))
        .height($r('app.float.button_height'))
        .margin({
          top: $r('app.float.button_margin_top')
        })
        .onClick(() =>{
          this.testOneInput()
        })
    }
    .width(CommonConstants.FULL_PERCENT)
    .height(CommonConstants.FULL_PERCENT)
  }
}