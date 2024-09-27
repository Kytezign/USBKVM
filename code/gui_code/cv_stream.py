import cv2
import numpy as np
try:
    import linux_cam

except ImportError:
    print("TODO: suport other platforms")
    raise

def get_config():
    if linux_cam:
        return linux_cam.get_config()
    raise NotImplementedError("OOps")

def clear_config():
    if linux_cam:
        linux_cam.clear_config()


def resize_into_array(image, array):
    original_shape = (image.shape[1], image.shape[0])
    tmp = np.zeros((image.shape[0], image.shape[1], array.shape[2]), dtype=np.uint8)
    new_x, new_y = array.shape[1], array.shape[0]
    w_scale, h_scale = original_shape[0]/new_x, original_shape[1]/new_y
    if w_scale > h_scale:
        scale = w_scale
    else:
        scale = h_scale
    scaled_x, scaled_y = int(original_shape[0]/scale), int(original_shape[1]/scale)

    # image = cv2.resize(image, new_size, interpolation=cv2.INTER_AREA )
    y_offset = (new_y - scaled_y)//2
    x_offset = (new_x - scaled_x)//2

    cv2.cvtColor(image,  cv2.COLOR_RGB2RGBA, tmp)
    interp = cv2.INTER_AREA if scale < 1 else cv2.INTER_CUBIC
    cv2.resize(tmp, (scaled_x, scaled_y), interpolation=interp, dst=array[y_offset:y_offset+scaled_y, x_offset:x_offset+scaled_x] )


class VideoStream:
    def __init__(self):
        config_dict = get_config()
        video_source = config_dict["Device"]
        vid = cv2.VideoCapture(video_source, cv2.CAP_ANY, params=(cv2.CAP_PROP_HW_ACCELERATION, cv2.VIDEO_ACCELERATION_ANY))
        if "Size" in config_dict:
            vid.set(cv2.CAP_PROP_FRAME_WIDTH, config_dict["Size"][0])
            vid.set(cv2.CAP_PROP_FRAME_HEIGHT, config_dict["Size"][1])
        if "Format" in config_dict:
            four_cc = cv2.VideoWriter.fourcc(*config_dict["Format"])
            vid.set(cv2.CAP_PROP_FOURCC, four_cc)
        if "FPS" in config_dict:
            vid.set(cv2.CAP_PROP_FPS, config_dict["FPS"])


        if not vid.isOpened():
            raise ValueError("Unable to open video source", video_source)

        # Get video source width and height
        self.width = int(vid.get(cv2.CAP_PROP_FRAME_WIDTH))
        self.height = int(vid.get(cv2.CAP_PROP_FRAME_HEIGHT))

        if not vid.isOpened():
            print("Cannot open camera")
            exit()
        self.vid = vid


    def write_to_array(self, array):
        _, image = self.vid.read()
        if image.shape[:2] != array.shape[:2]:
            resize_into_array(image, array)
        else:            
            cv2.cvtColor(image,  cv2.COLOR_RGB2RGBA, array)      


    def get_image(self):
        _, image = self.vid.read()
        return image


if __name__ == "__main__":
    v = VideoStream()
