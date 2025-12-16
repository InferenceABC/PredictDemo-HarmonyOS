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
import { dataSharePredicates } from '@kit.ArkData';
import { fileIo as fs, ReadOptions, WriteOptions, Filter, ListFileOptions} from '@kit.CoreFileKit';

import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import promptAction from '@ohos.promptAction';
async function _getArrayByUri(uri: string) : Promise<ArrayBuffer[]>{
  let inputs: ArrayBuffer[] = []

  let file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
  Logger.info('MS_LITE_LOG: file fd: ' + file.fd);
  let inputBuffer = new ArrayBuffer(CommonConstants.ARRAY_BUFFER_SIZE);
  let readLen = fileIo.readSync(file.fd, inputBuffer);
  Logger.info('MS_LITE_LOG: readSync data to file succeed and inputBuffer size is:' + readLen);
  let imageSource = image.createImageSource(file.fd);
  let pixelMap = await imageSource.createPixelMap();
  let info = await pixelMap.getImageInfo();
  Logger.info('MS_LITE_LOG: info.width = ' + info.size.width);
  Logger.info('MS_LITE_LOG: info.height = ' + info.size.height);

  await pixelMap.scale(CommonConstants.MAX_ZOOM_VALUE / info.size.width,
    CommonConstants.MAX_ZOOM_VALUE / info.size.height)

  Logger.info('Scale success');

  await pixelMap.crop({
    x: CommonConstants.X_COORDINATE,
    y: CommonConstants.Y_COORDINATE,
    size: {
      height: CommonConstants.MODEL_INPUT_HEIGHT,
      width: CommonConstants.MODEL_INPUT_WIDTH
    }
  })

  Logger.info('Crop success');

  info = await pixelMap.getImageInfo();
  Logger.info('MS_LITE_LOG: crop info.width = ' + info.size.width);
  Logger.info('MS_LITE_LOG: crop info.height = ' + info.size.height);

  const readBuffer = new ArrayBuffer(
    CommonConstants.MODEL_INPUT_HEIGHT * CommonConstants.MODEL_INPUT_WIDTH * 4
  );
  await pixelMap.readPixelsToBuffer(readBuffer);

  Logger.info('MS_LITE_LOG: Succeeded in reading image pixel data, buffer: ' +
  readBuffer.byteLength);
  const imageArr = new Uint8Array(
    readBuffer.slice(0, CommonConstants.MODEL_INPUT_HEIGHT * CommonConstants.MODEL_INPUT_WIDTH * 4));
  Logger.info('MS_LITE_LOG: imageArr length: ' + imageArr.length);
  let float32View = new Float32Array(CommonConstants.MODEL_INPUT_HEIGHT * CommonConstants.MODEL_INPUT_WIDTH * 3);
  let index = 0;
  for (let i = 0; i < imageArr.length; i++) {
    if ((i + 1) % 4 == 0) {
      float32View[index] = (imageArr[i - 3] / CommonConstants.RGB_MAX_VALUE - CommonConstants.MEANS[0]) / CommonConstants.STDS[0]; // B
      float32View[index+1] = (imageArr[i - 2] / CommonConstants.RGB_MAX_VALUE - CommonConstants.MEANS[1]) / CommonConstants.STDS[1]; // G
      float32View[index+2] = (imageArr[i - 1] / CommonConstants.RGB_MAX_VALUE - CommonConstants.MEANS[2]) / CommonConstants.STDS[2]; // R
      index += 3;
    }
  }
  Logger.info('MS_LITE_LOG: float32View length: ' + float32View.length);
  let printStr = 'float32View data:';
  for (let i = 0; i < 20; i++) {
    printStr += ' ' + float32View[i];
  }
  Logger.info('MS_LITE_LOG: float32View data: ' + printStr);
  inputs = [float32View.buffer]

  fileIo.closeSync(file)
  Logger.info('=========MS_LITE_LOG PREPROCESS END=========');
  return Promise.resolve(inputs)
}

async function getArrayByUriDebug(uri: string) : Promise<ArrayBuffer[]>{
  let inputs: ArrayBuffer[] = []

  let file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
  Logger.info('MS_LITE_LOG: file fd: ' + file.fd);
  let inputBuffer = new ArrayBuffer(CommonConstants.ARRAY_BUFFER_SIZE);
  let readLen = fileIo.readSync(file.fd, inputBuffer);
  Logger.info('MS_LITE_LOG: readSync data to file succeed and inputBuffer size is:' + readLen);
  let imageSource = image.createImageSource(file.fd);
  let pixelMap = await imageSource.createPixelMap();
  let info = await pixelMap.getImageInfo();
  Logger.info('MS_LITE_LOG: info.width = ' + info.size.width);
  Logger.info('MS_LITE_LOG: info.height = ' + info.size.height);

  pixelMap.scale(CommonConstants.MAX_ZOOM_VALUE / info.size.width,
    CommonConstants.MAX_ZOOM_VALUE / info.size.height).then(() => {
    pixelMap.crop(
      { x: CommonConstants.X_COORDINATE,
        y: CommonConstants.Y_COORDINATE,
        size: { height: CommonConstants.MODEL_INPUT_HEIGHT, width: CommonConstants.MODEL_INPUT_WIDTH } }
    ).then(async () => {
      let info = await pixelMap.getImageInfo();
      Logger.info('MS_LITE_LOG: crop info.width = ' + info.size.width);
      Logger.info('MS_LITE_LOG: crop info.height = ' + info.size.height);
      let readBuffer = new ArrayBuffer(CommonConstants.MODEL_INPUT_HEIGHT * CommonConstants.MODEL_INPUT_WIDTH * 4);
      await pixelMap.readPixelsToBuffer(readBuffer);
      Logger.info('MS_LITE_LOG: Succeeded in reading image pixel data, buffer: ' +
      readBuffer.byteLength);
      const imageArr = new Uint8Array(
        readBuffer.slice(0, CommonConstants.MODEL_INPUT_HEIGHT * CommonConstants.MODEL_INPUT_WIDTH * 4));
      Logger.info('MS_LITE_LOG: imageArr length: ' + imageArr.length);
      let float32View = new Float32Array(CommonConstants.MODEL_INPUT_HEIGHT * CommonConstants.MODEL_INPUT_WIDTH * 3);
      let index = 0;
      for (let i = 0; i < imageArr.length; i++) {
        if ((i + 1) % 4 == 0) {
          float32View[index] = (imageArr[i - 3] / CommonConstants.RGB_MAX_VALUE - CommonConstants.MEANS[0]) / CommonConstants.STDS[0]; // B
          float32View[index+1] = (imageArr[i - 2] / CommonConstants.RGB_MAX_VALUE - CommonConstants.MEANS[1]) / CommonConstants.STDS[1]; // G
          float32View[index+2] = (imageArr[i - 1] / CommonConstants.RGB_MAX_VALUE - CommonConstants.MEANS[2]) / CommonConstants.STDS[2]; // R
          index += 3;
        }
      }
      Logger.info('MS_LITE_LOG: float32View length: ' + float32View.length);
      let printStr = 'float32View data:';
      for (let i = 0; i < 20; i++) {
        printStr += ' ' + float32View[i];
      }
      Logger.info('MS_LITE_LOG: float32View data: ' + printStr);
      inputs = [float32View.buffer]
      })
    });
  fileIo.closeSync(file)
  Logger.info('=========MS_LITE_LOG PREPROCESS END=========');
  return Promise.resolve(inputs)
}

async function getArrayByUri(uri: string) {
  let file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
  Logger.info('MS_LITE_LOG: file fd1: ' + file.fd);
  let inputBuffer = new ArrayBuffer(CommonConstants.ARRAY_BUFFER_SIZE);
  let readLen = fileIo.readSync(file.fd, inputBuffer);
  Logger.info('MS_LITE_LOG: readSync data to file succeed and inputBuffer size is:' + readLen);
  let imageSource = image.createImageSource(file.fd);

  let pixelMap = await imageSource.createPixelMap();
  let info = await pixelMap.getImageInfo();
  Logger.info('MS_LITE_LOG: info.width = ' + info.size.width);
  Logger.info('MS_LITE_LOG: info.height = ' + info.size.height);
  try {
    pixelMap.scale(CommonConstants.MAX_ZOOM_VALUE / info.size.width,
    CommonConstants.MAX_ZOOM_VALUE / info.size.height)
  }catch (err) {
    Logger.info('err', err);
  }
  await pixelMap.crop(
    { x: CommonConstants.X_COORDINATE,
      y: CommonConstants.Y_COORDINATE,
      size: { height: CommonConstants.MODEL_INPUT_HEIGHT, width: CommonConstants.MODEL_INPUT_WIDTH } }
  )
  Logger.info('MS_LITE_LOG: crop info.width = ' + info.size.width);
  Logger.info('MS_LITE_LOG: crop info.height = ' + info.size.height);
  let readBuffer = new ArrayBuffer(CommonConstants.MODEL_INPUT_HEIGHT * CommonConstants.MODEL_INPUT_WIDTH * 4);
  await pixelMap.readPixelsToBuffer(readBuffer);
  Logger.info('MS_LITE_LOG: Succeeded in reading image pixel data, buffer: ' + readBuffer.byteLength);
  const imageArr = new Uint8Array(
      readBuffer.slice(0, CommonConstants.MODEL_INPUT_HEIGHT * CommonConstants.MODEL_INPUT_WIDTH * 4));
  Logger.info('MS_LITE_LOG: imageArr length: ' + imageArr.length);
  let float32View = new Float32Array(CommonConstants.MODEL_INPUT_HEIGHT * CommonConstants.MODEL_INPUT_WIDTH * 3);
  let index = 0;
  for (let i = 0; i < imageArr.length; i++) {
    if ((i + 1) % 4 == 0) {
      float32View[index] =
        (imageArr[i - 3] / CommonConstants.RGB_MAX_VALUE - CommonConstants.MEANS[0]) / CommonConstants.STDS[0]; // B
      float32View[index+1] =
        (imageArr[i - 2] / CommonConstants.RGB_MAX_VALUE - CommonConstants.MEANS[1]) / CommonConstants.STDS[1]; // G
      float32View[index+2] =
        (imageArr[i - 1] / CommonConstants.RGB_MAX_VALUE - CommonConstants.MEANS[2]) / CommonConstants.STDS[2]; // R
      index += 3;
    }
  }
  fileIo.closeSync(file)
  return float32View
}

async function requestMediaPermission(context: common.UIAbilityContext, ) {
  const atManager = abilityAccessCtrl.createAtManager();
  const permissions: Array<Permissions> = [
    'ohos.permission.READ_MEDIA',
  ];

  try {
    const result = await atManager.requestPermissionsFromUser(context, permissions);

    if (result.authResults.length === 0) {
      promptAction.showToast({ message: '权限请求被取消' });
      return false;
    }

    // 检查所有权限是否都获得授权
    const allGranted = result.authResults.every(granted => granted === 0);

    if (allGranted) {
      promptAction.showToast({ message: '媒体访问权限已授予' });
      return true;
    } else {
      // 处理部分权限被拒绝的情况
      const deniedPermissions = permissions.filter((_, index) => result.authResults[index] !== 0);
      promptAction.showToast({ message: `以下权限被拒绝: ${deniedPermissions.join(', ')}` });

      // 引导用户前往设置页面开启权限
      const want : Want= {
        action: 'ohos.settings.application',
        parameters: {
          bundleName: context.abilityInfo.bundleName,
          moduleName: context.abilityInfo.moduleName,
          abilityName: context.abilityInfo.name
        }
      };
      await context.startAbility(want);

      return false;
    }
  } catch (err) {
    const error = err as BusinessError;
    console.error(`权限请求失败: code=${error.code}, message=${error.message}`);
    return false;
  }
}

function copyfile(srcFilePath: string, dstFilePath: string) {
  let srcFile = fs.openSync(srcFilePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
  let destFile = fs.openSync(dstFilePath + '/destFile.txt', fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
  // 读取源文件内容并写入至目的文件
  let bufSize = 4096;
  let readSize = 0;
  let buf = new ArrayBuffer(bufSize);
  let readOptions: ReadOptions = {
    offset: readSize,
    length: bufSize
  };
  let readLen = fs.readSync(srcFile.fd, buf, readOptions);
  while (readLen > 0) {
    readSize += readLen;
    let writeOptions: WriteOptions = {
      length: readLen
    };
    fs.writeSync(destFile.fd, buf, writeOptions);
    readOptions.offset = readSize;
    readLen = fs.readSync(srcFile.fd, buf, readOptions);
  }
  // 关闭文件
  fs.closeSync(srcFile);
  fs.closeSync(destFile);
}

function generateModelChoiceString(out: Float32Array): string {
  // 1. 从数组中取出两个模型的分数
  // 假设 out[0] 是 DamoFD 的分数
  const damoFdScore: number = out[0];
  // 假设 out[1] 是 Retina 的分数
  const retinaScore: number = out[1];

  let chosenModel: string;
  let chosenScore: number;

  // 2. 比较分数并决定选择哪个模型
  if (damoFdScore > retinaScore) {
    chosenModel = "DamoFD";
    chosenScore = damoFdScore;
  } else if (retinaScore > damoFdScore) {
    chosenModel = "Retina";
    chosenScore = retinaScore;
  } else {
    // 处理分数相等的情况，这里默认选择 DamoFD
    chosenModel = "DamoFD (分数相等)";
    chosenScore = damoFdScore;
  }

  // 3. 构建结果字符串
  // 为了美观，我们通常将浮点数分数保留固定的小数位数（例如 4 位）

  // 第一行：显示两个模型的分数
  const scoreLine = `DamoFD分数: ${damoFdScore.toFixed(4)}，Retina分数: ${retinaScore.toFixed(4)}`;

  // 第二行：显示选择结果
  const choiceLine = `选择${chosenModel}模型，分数为 ${chosenScore.toFixed(4)}`;

  // 使用 \n 实现换行
  const resultString = scoreLine + '\n' + choiceLine;

  return resultString;
}


@Entry
@Component
struct Index {
  @State uris: Array<string> = [];
  @State max: number = 0;
  @State maxIndex: number = 0;
  @State maxArray: Array<number> = [];
  @State maxIndexArray: Array<number> = [];
  @State fileNameShow: number = 0;
  @State photoShow: number = 0;
  @State fileName: string = '';
  @State predictResultShow: number = 0;
  @State predictText: string = '';
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  processImage(): void {
    this.fileNameShow = 0;
    this.photoShow = 1;

    let resMgr: resourceManager.ResourceManager = this.context.getApplicationContext().resourceManager;
    resMgr.getRawFileContent(CommonConstants.MODEL_NAME).then(modelBuffer => {
      let photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 3;
      let photoPicker = new photoAccessHelper.PhotoViewPicker();
      photoPicker.select(photoSelectOptions, async (
        err: BusinessError, photoSelectResult: photoAccessHelper.PhotoSelectResult) => {
        if (err) {
          Logger.error('MS_LITE_ERR: PhotoViewPicker.select failed with err: ' + JSON.stringify(err));
          return;
        }
        Logger.info('MS_LITE_LOG: PhotoViewPicker.select successfully, ' +
          'photoSelectResult uri: ' + JSON.stringify(photoSelectResult));
        this.uris = photoSelectResult.photoUris;
        Logger.info('MS_LITE_LOG: uri: ' + this.uris);
        try {
          let file = fileIo.openSync(this.uris[0], fileIo.OpenMode.READ_ONLY);
          Logger.info('MS_LITE_LOG: file fd: ' + file.fd);
          let inputBuffer = new ArrayBuffer(CommonConstants.ARRAY_BUFFER_SIZE);
          let readLen = fileIo.readSync(file.fd, inputBuffer);
          Logger.info('MS_LITE_LOG: readSync data to file succeed and inputBuffer size is:' + readLen);
          let imageSource = image.createImageSource(file.fd);
          let pixelMap = await imageSource.createPixelMap();
          let info = await pixelMap.getImageInfo();
          Logger.info('MS_LITE_LOG: info.width = ' + info.size.width);
          Logger.info('MS_LITE_LOG: info.height = ' + info.size.height);
          pixelMap.scale(CommonConstants.MAX_ZOOM_VALUE / info.size.width,
            CommonConstants.MAX_ZOOM_VALUE / info.size.height).then(() => {
            pixelMap.crop(
              { x: CommonConstants.X_COORDINATE,
                y: CommonConstants.Y_COORDINATE, 
                size: { height: CommonConstants.MODEL_INPUT_HEIGHT, width: CommonConstants.MODEL_INPUT_WIDTH } }
            ).then(async () => {
              let info = await pixelMap.getImageInfo();
              Logger.info('MS_LITE_LOG: crop info.width = ' + info.size.width);
              Logger.info('MS_LITE_LOG: crop info.height = ' + info.size.height);
              let readBuffer = new ArrayBuffer(CommonConstants.MODEL_INPUT_HEIGHT * CommonConstants.MODEL_INPUT_WIDTH * 4);
              await pixelMap.readPixelsToBuffer(readBuffer);
              Logger.info('MS_LITE_LOG: Succeeded in reading image pixel data, buffer: ' +
              readBuffer.byteLength);
              const imageArr = new Uint8Array(
                readBuffer.slice(0, CommonConstants.MODEL_INPUT_HEIGHT * CommonConstants.MODEL_INPUT_WIDTH * 4));
              Logger.info('MS_LITE_LOG: imageArr length: ' + imageArr.length);
              let float32View = new Float32Array(CommonConstants.MODEL_INPUT_HEIGHT * CommonConstants.MODEL_INPUT_WIDTH * 3);
              let index = 0;
              for (let i = 0; i < imageArr.length; i++) {
                if ((i + 1) % 4 == 0) {
                  float32View[index] = (imageArr[i - 3] / CommonConstants.RGB_MAX_VALUE - CommonConstants.MEANS[0]) / CommonConstants.STDS[0]; // B
                  float32View[index+1] = (imageArr[i - 2] / CommonConstants.RGB_MAX_VALUE - CommonConstants.MEANS[1]) / CommonConstants.STDS[1]; // G
                  float32View[index+2] = (imageArr[i - 1] / CommonConstants.RGB_MAX_VALUE - CommonConstants.MEANS[2]) / CommonConstants.STDS[2]; // R
                  index += 3;
                }
              }
              Logger.info('MS_LITE_LOG: float32View length: ' + float32View.length);
              let printStr = 'float32View data:';
              for (let i = 0; i < 20; i++) {
                printStr += ' ' + float32View[i];
              }
              Logger.info('MS_LITE_LOG: float32View data: ' + printStr);
              let inputs: ArrayBuffer[] = [float32View.buffer];
              // predict
              modelPredict(modelBuffer.buffer.slice(0), inputs).then(outputs => {
                Logger.info('=========MS_LITE_LOG: MS_LITE predict success=====');
                for (let i = 0; i < outputs.length; i++) {
                  let out = new Float32Array(outputs[i].getData());
                  let printStr = '';

                  this.max = 1;
                  this.maxIndex = 0;
                  this.maxArray = [];
                  this.maxIndexArray = [];

                  for (let j = 0; j < out.length; j++) {
                    printStr += out[j].toString() + ',';
                    this.maxArray.push(Math.round(out[j] * CommonConstants.TEN_THOUSAND))
                  }
                  Logger.info('MS_LITE_LOG: ' + printStr);

                  // let newArray = out.filter(value => value !== this.max)
                  // for (let n = 0; n < 5; n++) {
                  //   this.max = out[0];
                  //   this.maxIndex = 0;
                  //   for (let m = 0; m < newArray.length; m++) {
                  //     if (newArray[m] > this.max) {
                  //       this.max = newArray[m];
                  //       this.maxIndex = m;
                  //     }
                  //   }
                  //   let localMax: number = this.max;
                  //   let localMaxIndex: number = this.maxIndex;
                  //   this.maxArray.push(Math.round(localMax * CommonConstants.TEN_THOUSAND))
                  //   this.maxIndexArray.push(localMaxIndex)
                  //   newArray = newArray.filter(value => value !== this.max)
                  // }
                  Logger.info('MS_LITE_LOG: max:' + this.maxArray);
                  Logger.info('MS_LITE_LOG: maxIndex:' + this.maxIndexArray);
                }
                Logger.info('=========MS_LITE_LOG END=========');
              })
            })
          })
          fileIo.closeSync(file)
        } catch (err) {
          Logger.error('MS_LITE_LOG: uri: open file fd failed.' + err)
        }
      })
    })
  }

  async predictInput(): Promise<void> {
    this.fileNameShow = 1;
    this.photoShow = 0;
    this.uris = [];
    this.predictResultShow = 1;


    let context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    let filesDir = context.filesDir;
    let datasetDir = filesDir +'/data_archive/250801_damoyolo_emb'


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

      // let input = await _getArrayByUri(datasetDir + '/' + filenames[i])
      //
      // this.maxArray = []
      // this.fileName = datasetDir + '/' + filenames[i]
      //
      // console.log("Time Logger: start Predict %s", filenames[i])


      let output = await modelPredict(modelBuffer.buffer.slice(0), [inputArray.buffer])
      //
      let out = new Float32Array(output[0].getData());

      console.log("=========DEMO_LOG: Output Data=====", out)

      this.predictText = generateModelChoiceString(out)


      //
      // let printStr = '';
      //
      // for (let j = 0; j < out.length; j++) {
      //   printStr += out[j].toString() + ',';
      //   this.maxArray.push(Math.round(out[j] * CommonConstants.TEN_THOUSAND))
      // }
      // console.log("Time Logger: End %s", filenames[i])
      //
      // Logger.info(filenames[i] + ',MS_LITE_LOG PREDICT RESULT: ' + printStr);
    }

  }

  build() {
    Column(){
      Text($r('app.string.EntryAbility_label'))
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
      Text("人脸框检测模型")
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
      Button('example图片示例')
        .width($r('app.float.button_width'))
        .height($r('app.float.button_height'))
        .margin({
          top: $r('app.float.button_margin_top')
        })
        .onClick(()=>{
          this.predictInput()
        })
      Button('待开发')
        .width($r('app.float.button_width'))
        .height($r('app.float.button_height'))
        .margin({
          top: $r('app.float.button_margin_top')
        })
        .onClick(() =>{
          this.processImage()
        })
    }
    .width(CommonConstants.FULL_PERCENT)
    .height(CommonConstants.FULL_PERCENT)
  }
}