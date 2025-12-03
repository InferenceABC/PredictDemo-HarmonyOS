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

  await pixelMap.crop({
    x: CommonConstants.X_COORDINATE,
    y: CommonConstants.Y_COORDINATE,
    size: {
      height: CommonConstants.MODEL_INPUT_HEIGHT,
      width: CommonConstants.MODEL_INPUT_WIDTH
    }
  })

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
    this.max = 1;


    let context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    let filesDir = context.filesDir;
    let datasetDir = filesDir +'/dataset_InFi_0813/hw_pictures'

    let listFileOption: ListFileOptions = {
      recursion: false,
      listNum: 0,
      filter: {
        suffix: [".png", ".jpg", ".jpeg"],
        fileSizeOver: 4096
      }
    };
    let filenames = fs.listFileSync(datasetDir, listFileOption);
    console.info("listFile succeed");

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

      console.log("Time Logger: start PreProcess %s", filenames[i])
      let input = await _getArrayByUri(datasetDir + '/' + filenames[i])

      this.maxArray = []
      this.fileName = datasetDir + '/' + filenames[i]

      console.log("Time Logger: start Predict %s", filenames[i])
      let output = await modelPredict(modelBuffer.buffer.slice(0), input)

      console.log("Time Logger: start PostProcess %s", filenames[i])
      let out = new Float32Array(output[0].getData());

      let printStr = '';

      for (let j = 0; j < out.length; j++) {
        printStr += out[j].toString() + ',';
        this.maxArray.push(Math.round(out[j] * CommonConstants.TEN_THOUSAND))
      }
      console.log("Time Logger: End %s", filenames[i])

      Logger.info(filenames[i] + ',MS_LITE_LOG PREDICT RESULT: ' + printStr);



      // await getArrayByUriDebug(datasetDir + '/' + filenames[i]).then(
      //   input => {
      //     modelPredict(modelBuffer.buffer.slice(0), input).then(
      //       output => {
      //         console.log('predict success')
      //       }
      //     )
      //   }
      // );
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
      if(this.max){
        List(){
          ForEach(this.maxArray, (item: number, index: number) => {
            ListItem(){
              Row(){
                Text(CommonConstants.LABELS_NAME_MAP[index] + ': ')
                  .fontSize($r('app.float.common_font_size'))
                  .fontWeight(CommonConstants.FONT_WEIGHT_500)
                  .fontFamily($r('app.string.Font_family_black'))
                Text((this.maxArray[index] / 100).toString() + '%')
                  .fontSize($r('app.float.common_font_size'))
                  .fontWeight(CommonConstants.FONT_WEIGHT_500)
                  .fontFamily($r('app.string.Font_family_black'))
                  .textAlign(TextAlign.End)
              }
              .width(CommonConstants.FULL_PERCENT)
              .justifyContent(FlexAlign.SpaceBetween)
            }
            .height($r('app.float.list_item_height'))
          }, (item: number, index: number) => index + JSON.stringify(item))
        }
        .backgroundColor($r("app.color.list_background"))
        .borderRadius($r('sys.float.corner_radius_level8'))
        .divider({
          strokeWidth: $r('app.float.stroke_width'),
          color: $r('app.color.five_black')
        })
        .padding({
          left: $r('app.float.small_padding'),
          right: $r('app.float.small_padding')
        })
        .width($r('app.float.list_width'))
        .height($r('app.float.list_height'))
      } else {
        Blank()
          .width($r('app.float.blank_width'))
          .height($r('app.float.blank_height'))
      }
      Button('InFi全数据集测试')
        .width($r('app.float.button_width'))
        .height($r('app.float.button_height'))
        .onClick(()=>{
          this.predictInput()
        })
      Button('Picker选择图片测试')
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